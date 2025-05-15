----------------------------------------------------------------------------
--
--  CPUtoplevel.vhd
--
--  Top-level CPU module for SH-2 compatible processor.
--  This file instantiates and connects the Register Array, ALU, and DMAU.
--
--  Inputs:
--      - Control lines for register selection, ALU operations, and DMAU addressing
--  Outputs:
--      - ALU result and flags
--      - Data memory address bus and updated address source (for pre/post inc/dec)
--      - Program memory address bus and updated address source (for pre/post inc/dec)
--
--  Entities instantiated:
--      - RegArray
--      - ALU
--      - MemUnit (used as DMAU)
--      - MemUnit (used as PMAU)
--
--  Revision History:
--     16 Apr 25  Ruth Berkun       Initial revision. Added SH2RegArray, ALU, DMAU, PMAU integration.
--      7 May 35  Ruth Berkun       Restructure to have ctrl signals to say what updates 
--                                  SH2DataBus and SH2AddressBus buses
--      7 May 25  Ruth Berkun       Instantiate external memory
--      7 May 25  Nerissa Finnen    Started read-in file functionality
--      9 May 25  Nerissa Finnen    Updated IR constants. Started finite state machine functionality
--                                  and control signal settings. 
--     12 May 25  Ruth Berkun       Added over constants       
--     12 May 25  Nerissa Finnen    Finished finite state machine initial implementation, added 5 instructions    
--     12 May 25  Ruth Berkun       State machine adjustments, start process IR logic 
--                                  Add Enable signal: allow CPU and testbench to tell each other when they are reading/writing  
--     13 May 25  Ruth Berkun       Remove Enable signal, move memory out of CPU (oops why did we put it here)            
--     13 May 25  Nerissa Finnen    Added constant to hold and update the PMAU and DMAU properly 
--     14 May 25  Ruth Berkun       Fixed Address and Data bus muxing issue (set to high Z when testbench accesses it)
--                                  (And fixed corresponding setting of mux mode in finite state machine)
----------------------------------------------------------------------------

------------------------------------------------- Constants
library ieee;
use ieee.std_logic_1164.ALL;
package SH2_CPU_Constants is

    -- Memory instantiation
    constant memBlockWordSize : integer := 25;  -- 4 words in every memory block
    constant instrLen : integer := 16;

    -- Register and word size configuration
    constant regLen       : integer := 32;   -- Each register is 32 bits
    constant regCount     : integer := 18;   -- 16 general + 2 special registers (PR, SR)

    -- DMAU configuration
    constant dmauSourceCount  : integer := 4;    -- from reg array, GBR, VBR, or immediate
    constant dmauOffsetCount  : integer := 7;    -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    constant maxIncDecBitDMAU     : integer := 3;    -- Allow inc/dec up to bit 3 (+-4) 

        -- DMAU source select
    constant DMAU_SRC_SEL_GBR : integer := 0;
    constant DMAU_SRC_SEL_VBR : integer := 1;
    constant DMAU_SRC_SEL_REG : integer := 2;
    constant DMAU_SRC_SEL_IMM : integer := 3;

    -- DMAU offset select
    constant DMAU_OFFSET_SEL_ZEROES : integer := 0;
    constant DMAU_OFFSET_SEL_REG_OFFSET_x1 : integer := 1;
    constant DMAU_OFFSET_SEL_REG_OFFSET_x2 : integer := 2;
    constant DMAU_OFFSET_SEL_REG_OFFSET_x4 : integer := 3;
    constant DMAU_OFFSET_SEL_IMM_OFFSET_x1 : integer := 4;
    constant DMAU_OFFSET_SEL_IMM_OFFSET_x2 : integer := 5;
    constant DMAU_OFFSET_SEL_IMM_OFFSET_x4 : integer := 6;

    -- PMAU configuration
    constant pmauSourceCount  : integer := 3;    -- from reg array, PC, or immediate
    constant pmauOffsetCount  : integer := 7;    -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    constant maxIncDecBitPMAU     : integer := 3;    -- Allow inc/dec up to bit 3 (+-4)

    -- PMAU source select
    constant PMAU_SRC_SEL_PC : integer := 0;
    constant PMAU_SRC_SEL_REG : integer := 1;
    constant PMAU_SRC_SEL_IMM : integer := 2;

    -- PMAU offset select
    constant PMAU_OFFSET_SEL_ZEROES : integer := 0;
    constant PMAU_OFFSET_SEL_REG_OFFSET_x1 : integer := 1;
    constant PMAU_OFFSET_SEL_REG_OFFSET_x2 : integer := 2;
    constant PMAU_OFFSET_SEL_REG_OFFSET_x4 : integer := 3;
    constant PMAU_OFFSET_SEL_IMM_OFFSET_x1 : integer := 4;
    constant PMAU_OFFSET_SEL_IMM_OFFSET_x2 : integer := 5;
    constant PMAU_OFFSET_SEL_IMM_OFFSET_x4 : integer := 6;

    -- Flag bit positions (useful for flag bus indexing)
    constant FLAG_INDEX_CARRYOUT     : integer := 4;
    constant FLAG_INDEX_HALF_CARRY   : integer := 3;
    constant FLAG_INDEX_OVERFLOW     : integer := 2;
    constant FLAG_INDEX_ZERO         : integer := 1;
    constant FLAG_INDEX_SIGN         : integer := 0;

    -- Special register indices
    constant REG_PR            : integer := 16;
    constant REG_SR            : integer := 17;

    -- Choosing data and address bus indicies
    constant NUM_DATA_BUS_OPTIONS : integer := 3; -- ALU, regs, hold, open
    constant NUM_ADDRESS_BUS_OPTIONS : integer := 3; -- DMAU, PMAU, hold, open
    constant OPEN_DATA_BUS : integer := 0;
    constant HOLD_DATA_BUS : integer := 1;
    constant SET_DATA_BUS_TO_REG_A_OUT : integer := 2;
    constant SET_DATA_BUS_TO_ALU_OUT : integer := 3;
    constant OPEN_ADDRESS_BUS : integer := 0;
    constant HOLD_ADDRESS_BUS : integer := 1;
    constant SET_ADDRESS_BUS_TO_PMAU_OUT : integer := 2;
    constant SET_ADDRESS_BUS_TO_DMAU_OUT : integer := 3;

    -- Holding settings for DMAU and PMAU; ensures that the register 
    -- is held at current value by decrementing by 1 and adding 1 as offset
    constant PMAU_RESET         : std_logic := '0';     --Resets the PC value in the PMAU
    constant PMAU_NO_RESET         : std_logic := '1';     --Resets the PC value in the PMAU
    constant DEFAULT_SRC_SEL    : integer := 0;         --May change due to PC/GBR location moving
    constant DEFAULT_DEC_SEL    : std_logic := '1';     --Select decrement
    constant DEFAULT_DEC_BIT    : integer := 0;         --Only 0th bit to modify
    constant DEFAULT_POST_SEL   : std_logic := '1';     --Post decrement and preserve the initial value
    constant DEFAULT_OFFSET_SEL : integer := 4;         --Select immediate offset multiplied by 1
    constant DEFAULT_OFFSET_VAL : std_logic_vector(31 downto 0) := "00000000000000000000000000000001";    --Set the offset to be 1

    -- Incrementing in PMAU
    constant DEFAULT_PRE_SEL    : std_logic := '1';
    constant DEFAULT_INC_SEL    : std_logic := '0';
    constant DEFAULT_NO_OFF_VAL : integer := 0;

    -- Incrementing in DMAU

    -- PC clock increments
    constant ONE_CLOCK      : std_logic_vector(31 downto 0) := "00000000000000000000000000000001";
    constant TWO_CLOCK      : std_logic_vector(31 downto 0) := "00000000000000000000000000000010";
    constant THREE_CLOCK    : std_logic_vector(31 downto 0) := "00000000000000000000000000000011";
    constant FOUR_CLOCK     : std_logic_vector(31 downto 0) := "00000000000000000000000000000100";

end SH2_CPU_Constants;

library ieee;
use ieee.std_logic_1164.ALL;
package SH2_IR_Constants is
    -- SH-2 Instruction Opcode Constants
    -- Register, immediate, and specified registers
    constant ADD_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1100";
    constant ADD_imm_Rn : std_logic_vector(15 downto 0) := "0111XXXXXXXXXXXX";
    constant ADDC_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1110";
    constant ADDV_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1111";
    constant AND_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1001";
    constant AND_imm_R0 : std_logic_vector(15 downto 0) := "11001001XXXXXXXX";
    constant AND_B_imm_GBR : std_logic_vector(15 downto 0) := "11001101XXXXXXXX";
    constant BF_disp : std_logic_vector(15 downto 0) := "10001011XXXXXXXX";
    constant BF_S_disp : std_logic_vector(15 downto 0) := "10001111XXXXXXXX";
    constant BRA_disp : std_logic_vector(15 downto 0) := "1010XXXXXXXXXXXX";
    constant BRAF_Rm : std_logic_vector(15 downto 0) := "0000XXXX00100011";
    constant BSR_disp : std_logic_vector(15 downto 0) := "1011XXXXXXXXXXXX";
    constant BSRF_Rm : std_logic_vector(15 downto 0) := "0000XXXX00000011";
    constant BT_disp : std_logic_vector(15 downto 0) := "10001001XXXXXXXX";
    constant BT_S_disp : std_logic_vector(15 downto 0) := "10001101XXXXXXXX";
    --constant CLRMAC : std_logic_vector(15 downto 0) := "0000000000101000";
    constant CLRT : std_logic_vector(15 downto 0) := "0000000000001000";
    constant CMP_EQ_imm_R0 : std_logic_vector(15 downto 0) := "10001000XXXXXXXX";
    constant CMP_EQ_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0000";
    constant CMP_GE_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0011";
    constant CMP_GT_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0111";
    constant CMP_HI_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0110";
    constant CMP_HS_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0010";
    constant CMP_PL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00010101";
    constant CMP_PZ_Rn : std_logic_vector(15 downto 0) := "0100XXXX00010001";
    constant CMP_STR_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1100";
    --constant DIV0S_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX0111";
    --constant DIV0U : std_logic_vector(15 downto 0) := "0000000000011001";
    --constant DIV1_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0100";
    --constant DMULS_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1101";
    --constant DMULU_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX0101";
    constant DT_Rn : std_logic_vector(15 downto 0) := "0100XXXX00010000";
    constant EXTS_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1110";
    constant EXTS_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1111";
    constant EXTU_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1100";
    constant EXTU_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1101";
    constant JMP_Rm : std_logic_vector(15 downto 0) := "0100XXXX00101011";
    constant JSR_Rm : std_logic_vector(15 downto 0) := "0100XXXX00001011";
    constant LDC_Rm_SR : std_logic_vector(15 downto 0) := "0100XXXX00001110";
    constant LDC_Rm_GBR : std_logic_vector(15 downto 0) := "0100XXXX00011110";
    constant LDC_Rm_VBR : std_logic_vector(15 downto 0) := "0100XXXX00101110";
    constant LDC_L_Rm_SR : std_logic_vector(15 downto 0) := "0100XXXX00000111";
    constant LDC_L_Rm_GBR : std_logic_vector(15 downto 0) := "0100XXXX00010111";
    constant LDC_L_Rm_VBR : std_logic_vector(15 downto 0) := "0100XXXX00100111";
    --constant LDS_Rm_MACH : std_logic_vector(15 downto 0) := "0100XXXX00001010";
    --constant LDS_Rm_MACL : std_logic_vector(15 downto 0) := "0100XXXX00011010";
    constant LDS_Rm_PR : std_logic_vector(15 downto 0) := "0100XXXX00101010";
    --constant LDS_L_Rm_MACH : std_logic_vector(15 downto 0) := "0100XXXX00000110";
    --constant LDS_L_Rm_MACL : std_logic_vector(15 downto 0) := "0100XXXX00010110";
    constant LDS_L_Rm_PR : std_logic_vector(15 downto 0) := "0100XXXX00100110";
    --constant MAC_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000XXXXXXXX1111";
    --constant MAC_W_Rm_Rn : std_logic_vector(15 downto 0) := "0100XXXXXXXX1111";
    constant MOV_IMM_TO_Rn        : std_logic_vector(15 downto 0) := "1110XXXXXXXXXXXX"; -- MOV #imm, Rn
    constant MOV_W_PC_DISP_TO_Rn  : std_logic_vector(15 downto 0) := "1001XXXXXXXXXXXX"; -- MOV.W @(disp,PC), Rn
    constant MOV_L_PC_DISP_TO_Rn  : std_logic_vector(15 downto 0) := "1101XXXXXXXXXXXX"; -- MOV.L @(disp,PC), Rn
    constant MOV_Rm_TO_Rn         : std_logic_vector(15 downto 0) := "0110XXXXXXXX0011"; -- MOV Rm, Rn
    constant MOVB_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010XXXXXXXX0000"; -- MOV.B Rm, @Rn
    constant MOVW_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010XXXXXXXX0001"; -- MOV.W Rm, @Rn
    constant MOVL_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010XXXXXXXX0010"; -- MOV.L Rm, @Rn
    constant MOVB_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110XXXXXXXX0000"; -- MOV.B @Rm, Rn
    constant MOVW_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110XXXXXXXX0001"; -- MOV.W @Rm, Rn
    constant MOVL_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110XXXXXXXX0010"; -- MOV.L @Rm, Rn
    constant MOVB_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010XXXXXXXX0100"; -- MOV.B Rm, @–Rn
    constant MOVW_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010XXXXXXXX0101"; -- MOV.W Rm, @–Rn
    constant MOVL_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010XXXXXXXX0110"; -- MOV.L Rm, @–Rn
    constant MOVB_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX0100"; -- MOV.B @Rm+, Rn
    constant MOVW_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX0101"; -- MOV.W @Rm+, Rn
    constant MOVL_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX0110"; -- MOV.L @Rm+, Rn
    constant MOVB_R0_TO_atDispRn  : std_logic_vector(15 downto 0) := "10000000XXXXXXXX"; -- MOV.B R0, @(disp,Rn)
    constant MOVW_R0_TO_atDispRn  : std_logic_vector(15 downto 0) := "10000001XXXXXXXX"; -- MOV.W R0, @(disp,Rn)
    constant MOVL_Rm_TO_atDispRn  : std_logic_vector(15 downto 0) := "0001XXXXXXXXXXXX"; -- MOV.L Rm, @(disp,Rn)
    constant MOVB_atDispRm_TO_R0  : std_logic_vector(15 downto 0) := "10000100XXXXXXXX"; -- MOV.B @(disp,Rm), R0
    constant MOVW_atDispRm_TO_R0  : std_logic_vector(15 downto 0) := "10000101XXXXXXXX"; -- MOV.W @(disp,Rm), R0
    constant MOVL_atDispRm_TO_Rn  : std_logic_vector(15 downto 0) := "0101XXXXXXXXXXXX"; -- MOV.L @(disp,Rm), Rn
    constant MOVB_Rm_TO_atR0Rn    : std_logic_vector(15 downto 0) := "0000XXXXXXXX0100"; -- MOV.B Rm, @(R0,Rn)
    constant MOVW_Rm_TO_atR0Rn    : std_logic_vector(15 downto 0) := "0000XXXXXXXX0101"; -- MOV.W Rm, @(R0,Rn)  
    constant MOV_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000XXXXXXXX0110";
    constant MOV_B_GBR_R0 : std_logic_vector(15 downto 0) := "11000000XXXXXXXX";
    constant MOV_W_GBR_R0 : std_logic_vector(15 downto 0) := "11000001XXXXXXXX";
    constant MOV_L_GBR_R0 : std_logic_vector(15 downto 0) := "11000010XXXXXXXX";
    constant MOV_B_R0_GBR : std_logic_vector(15 downto 0) := "11000100XXXXXXXX";
    constant MOV_W_R0_GBR : std_logic_vector(15 downto 0) := "11000101XXXXXXXX";
    constant MOV_L_R0_GBR : std_logic_vector(15 downto 0) := "11000110XXXXXXXX";
    constant MOVA_PC_R0 : std_logic_vector(15 downto 0) := "11000111XXXXXXXX";
    constant MOVT_Rn : std_logic_vector(15 downto 0) := "0000XXXX00101001";
    --constant MUL_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000XXXXXXXX0111";
    --constant MULS_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1111";
    --constant MULU_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1110";
    constant NEG_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1011";
    constant NEGC_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1010";
    constant NOP : std_logic_vector(15 downto 0) := "0000000000001001";
    constant NOT_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX0111";
    constant OR_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1011";
    constant OR_imm_R0 : std_logic_vector(15 downto 0) := "11001011XXXXXXXX";
    constant OR_B_imm_GBR : std_logic_vector(15 downto 0) := "11001111XXXXXXXX";
    constant ROTCL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100100";
    constant ROTCR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100101";
    constant ROTL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000100";
    constant ROTR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000101";
    constant RTE : std_logic_vector(15 downto 0) := "0000000000101011";
    constant RTS : std_logic_vector(15 downto 0) := "0000000000001011";
    constant SETT : std_logic_vector(15 downto 0) := "0000000000011000";
    constant SHAL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100000";
    constant SHAR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100001";
    constant SHLL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000000";
    constant SHLR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000001";
    --constant SHLL2_Rn : std_logic_vector(15 downto 0) := "0100XXXX00001000";
    --constant SHLR2_Rn : std_logic_vector(15 downto 0) := "0100XXXX00001001";
    --constant SHLL8_Rn : std_logic_vector(15 downto 0) := "0100XXXX00011000";
    --constant SHLR8_Rn : std_logic_vector(15 downto 0) := "0100XXXX00011001";
    --constant SHLL16_Rn : std_logic_vector(15 downto 0) := "0100XXXX00101000";
    --constant SHLR16_Rn : std_logic_vector(15 downto 0) := "0100XXXX00101001";
    constant SLEEP : std_logic_vector(15 downto 0) := "0000000000011011";
    constant STC_SR_Rn : std_logic_vector(15 downto 0) := "0000XXXX00000010";
    constant STC_GBR_Rn : std_logic_vector(15 downto 0) := "0000XXXX00010010";
    constant STC_VBR_Rn : std_logic_vector(15 downto 0) := "0000XXXX00100010";
    constant STC_L_SR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000011";
    constant STC_L_GBR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00010011";
    constant STC_L_VBR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100011";
    --constant STS_MACH_Rn : std_logic_vector(15 downto 0) := "0000XXXX00001010";
    --constant STS_MACL_Rn : std_logic_vector(15 downto 0) := "0000XXXX00011010";
    constant STS_PR_Rn : std_logic_vector(15 downto 0) := "0000XXXX00101010";
    --constant STS_L_MACH_Rn : std_logic_vector(15 downto 0) := "0100XXXX00000010";
    --constant STS_L_MACL_Rn : std_logic_vector(15 downto 0) := "0100XXXX00010010";
    constant STS_L_PR_Rn : std_logic_vector(15 downto 0) := "0100XXXX00100010";
    constant SUB_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1000";
    constant SUBC_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1010";
    constant SUBV_Rm_Rn : std_logic_vector(15 downto 0) := "0011XXXXXXXX1011";
    constant SWAP_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1000";
    constant SWAP_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110XXXXXXXX1001";
    constant TAS_B_Rn : std_logic_vector(15 downto 0) := "0100XXXX00011011";
    constant TRAPA_imm : std_logic_vector(15 downto 0) := "11000011XXXXXXXX";
    constant TST_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1000";
    constant TST_imm_R0 : std_logic_vector(15 downto 0) := "11001000XXXXXXXX";
    constant TST_B_imm_GBR : std_logic_vector(15 downto 0) := "11001100XXXXXXXX";
    constant XTRCT_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1101";
    constant XOR_Rm_Rn : std_logic_vector(15 downto 0) := "0010XXXXXXXX1010";
    constant XOR_imm_R0 : std_logic_vector(15 downto 0) := "11001010XXXXXXXX";
    constant XOR_B_imm_GBR : std_logic_vector(15 downto 0) := "11001110XXXXXXXX";
end SH2_IR_Constants;

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.SH2_CPU_Constants.all;
use work.SH2_IR_Constants.all;
use work.array_type_pkg.all;
use ieee.std_logic_textio.all;  -- Needed for to_hstring


entity CPUtoplevel is
    port(
        
        Reset   :  in     std_logic;                       -- reset signal (active low)

        NMI     :  in     std_logic;                       -- non-maskable interrupt signal (falling edge)
        INT     :  in     std_logic;                       -- maskable interrupt signal (active low)

        RE0     :  out    std_logic;                       -- first byte active low read enable
        RE1     :  out    std_logic;                       -- second byte active low read enable
        RE2     :  out    std_logic;                       -- third byte active low read enable
        RE3     :  out    std_logic;                       -- fourth byte active low read enable
        WE0     :  out    std_logic;                       -- first byte active low write enable
        WE1     :  out    std_logic;                       -- second byte active low write enable
        WE2     :  out    std_logic;                       -- third byte active low write enable
        WE3     :  out    std_logic;                       -- fourth byte active low write enable

        SH2clock      : in std_logic;
        SH2DataBus : buffer  std_logic_vector(regLen - 1 downto 0);   -- stores data to read/write from memory
        SH2AddressBus : buffer  std_logic_vector(regLen - 1 downto 0)   -- stores address to read/write from memory

    );
end CPUtoplevel;

 
architecture Structural of CPUtoplevel is

    -- Constants --
    --====================================================================================================================
    constant REG_LEN_ZEROS : std_logic_vector(regLen-1 downto 0) := (others => '0');
    constant INSTR_LEN_ZEROS : std_logic_vector(instrLen-1 downto 0) := (others => '0');

    -- Control Signals --
    --==================================================================================================================================================
    ------------------------------------------------------------------------------------------------------------------
    -- REG ARRAY FROM CONTROL UNIT INPUTS (for selecting reg in/out control)
    signal SH2RegIn      : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal SH2RegInSel   : integer  range regCount - 1 downto 0 := 0;
    signal SH2RegStore   : std_logic := '0';
    signal SH2RegASel    : integer  range regCount - 1 downto 0 := 0;
    signal SH2RegBSel    : integer  range regCount - 1 downto 0 := 0;
    signal SH2RegAx      : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal SH2RegAxIn    : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal SH2RegAxInSel : integer  range regCount - 1 downto 0 := 0;
    signal SH2RegAxStore : std_logic := '0';
    signal SH2RegA1Sel   : integer  range regCount - 1 downto 0 := 0;
    signal SH2RegA2Sel   : integer  range regCount - 1 downto 0 := 0;
    ------------------------------------------------------------------------------------------------------------------
    -- ALU FROM CONTROL UNIT INPUTS (for ALU operation control)
    signal SH2FCmd     : std_logic_vector(3 downto 0) := (others => '0');         -- F-Block operation
    signal SH2CinCmd   : std_logic_vector(1 downto 0) := (others => '0');         -- carry in operation
    signal SH2SCmd     : std_logic_vector(2 downto 0) := (others => '0');         -- shift operation
    signal SH2ALUCmd   : std_logic_vector(1 downto 0) := (others => '0');         -- ALU result select
    signal SH2Cin      : std_logic;
    -- ALU additional from control line inputs (not directly from generic ALU)
    signal SH2ALUImmediateOperand      : std_logic_vector(regLen-1 downto 0) := (others => '0'); -- control unit should pad it (with 1s or 0s
                                                                                                -- based on whether it's signed or not)
                                                                                                -- before giving us immediate operand
    signal SH2ALUUseImmediateOperand   : std_logic; -- 1 for use immediate operand, 0 otherwise
    -- ALU OUTPUTS
    signal SH2ALUResult   : std_logic_vector(regLen - 1 downto 0) := (others => '0');            -- ALU result
    signal FlagBus        : std_logic_vector(4 downto 0) := (others => '0');                     -- Flags are Cout, HalfCout, Overflow, Zero, Sign
    ------------------------------------------------------------------------------------------------------------------
    -- DMAU FROM CONTROL LINE INPUTS
    signal SH2DMAUReset      : std_logic := '0';
    signal SH2DMAUSrcSel     : integer  range dmauSourceCount - 1 downto 0 := 0;
    signal SH2DMAUOffsetSel  : integer  range dmauOffsetCount - 1 downto 0 := 0;
    signal SH2DMAUIncDecSel  : std_logic := '0';
    signal SH2DMAUIncDecBit  : integer  range maxIncDecBitDMAU downto 0 := 0;
    signal SH2DMAUPrePostSel : std_logic := '0';
    -- DMAU added inputs (not directly from generic MAU)
    signal DMAUImmediateSource :  std_logic_vector(regLen-1 downto 0) := (others => '0');
    signal DMAUImmediateOffset :  std_logic_vector(regLen-1 downto 0) := (others => '0');
    -- DMAU OUTPUTS
    signal SH2DataAddressBus : std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- DMAU input address, updated
                                                                                        -- (Need control line to see which src)
    signal SH2DataAddressSrc : std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- DMAU input address, updated
                                                                                        -- (Need control line to see which src)
    -------------------------------------------------------------------------------------
    -- PMAU FROM CONTROL LINE INPUTS
    signal SH2PMAUReset      : std_logic := '0';
    signal SH2PMAUSrcSel     : integer  range pmauSourceCount - 1 downto 0 := 0;
    signal SH2PMAUOffsetSel  : integer  range pmauOffsetCount - 1 downto 0 := 0;
    signal SH2PMAUIncDecSel  : std_logic := '0';
    signal SH2PMAUIncDecBit  : integer  range maxIncDecBitPMAU downto 0 := 0;
    signal SH2PMAUPrePostSel : std_logic := '0';
    -- PMAU added inputs (not directly from generic MAU)
    signal PMAUImmediateSource : std_logic_vector(regLen-1 downto 0) := (others => '0');
    signal PMAUImmediateOffset : std_logic_vector(regLen-1 downto 0) := (others => '0');
    
    -- PMAU OUTPUTS
    signal SH2ProgramAddressBus : std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- PMAU input address, updated
                                                                                            -- (Control unit uses to update PC)
    ------------------------------------------------------------------------------------------
    
    -- Outputs
    --==================================================================================================================================================
    -- CONTROL OUTPUTS
    signal SH2SelDataBus    : integer range NUM_DATA_BUS_OPTIONS downto 0 := OPEN_DATA_BUS;     -- do not update, update with reg output, or update with ALU output
    signal SH2SelAddressBus : integer range NUM_ADDRESS_BUS_OPTIONS downto 0 := OPEN_ADDRESS_BUS;  -- do not update, update with PMAU address out, or update with DMAU address out
    ------------------------------------------------------------------------------------------
    -- Outputs of registers; get hooked up to ALU and PMAU and DMAU
    signal RegArrayOutA  : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal RegArrayOutB  : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal RegArrayOutA1 : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal RegArrayOutA2 : std_logic_vector(regLen - 1 downto 0) := (others => '0');

    signal SH2PC : std_logic_vector(regLen - 1 downto 0) := (others => '0'); -- the PC: a very special register!
    ------------------------------------------------------------------------------------------

    -- Signals and states
    --==================================================================================================================================================
    -- CPU top level signals; finite state machine and IR
    type states is (ZERO_CLK, FETCH_IR, END_OF_FILE); 
    --TWO_CLK_W, TWO_CLK_R, THREE_CLK_R, THREE_CLK_W);
    signal CurrentState     : states;
    signal NextState      : states; --ughghghhggh

    signal InstructionReg   : std_logic_vector(instrLen - 1 downto 0); -- IR
    signal ClockCounter     : std_logic_vector(regLen - 1 downto 0); -- what clock cycle are we on?
    signal store_opcode_in_low_byte : std_logic := '0';  -- store in high byte then low byte

begin

    -- ================================================================================================== Entity Instantiations
    -- Instantiate register array
    SH2RegArray : entity work.SH2RegArray
        port map (
            SH2RegIn      => SH2RegIn,         -- hook up to port inputs
            SH2RegInSel   => SH2RegInSel,      -- so control unit can input
            SH2RegStore   => SH2RegStore,  
            SH2RegASel    => SH2RegASel,
            SH2RegBSel    => SH2RegBSel,
            SH2RegAxIn    => SH2RegAxIn,
            Sh2RegAxInSel => SH2RegAxInSel,
            SH2RegAxStore => SH2RegAxStore,
            SH2RegA1Sel   => SH2RegA1Sel,
            SH2RegA2Sel   => SH2RegA2Sel,
            SH2clock      => SH2clock,
            SH2RegA       => RegArrayOutA,
            SH2RegB       => RegArrayOutB,
            SH2RegA1      => RegArrayOutA1,
            SH2RegA2      => RegArrayOutA2
        );


    -- Instantiate ALU
    SH2ALU : entity work.SH2ALU
        port map (
            SH2ALUOpA   => RegArrayOutA,              -- Control unit will set operands,
            SH2ALUOpB   => RegArrayOutB,              -- to be output from the register array (if they so exist)
            SH2ALUImmediateOperand => SH2ALUImmediateOperand,           -- can also be immediate (in instruction)
            SH2ALUUseImmediateOperand => SH2ALUUseImmediateOperand, 
            SH2Cin      =>  RegArrayOutA1(0), -- Cin comes from T bit of SR, which is the rightmost bit                    
            SH2FCmd     => SH2FCmd, 
            SH2CinCmd   => SH2CinCmd, 
            SH2SCmd     => SH2SCmd, 
            SH2ALUCmd   => SH2ALUCmd, 
            SH2ALUResult   => SH2ALUResult,  -- now we are just hooking up outputs
            FlagBus     => FlagBus
        );

    -- Instantiate DMAU
    SH2DMAU : entity  work.SH2DMAU
        port map(
  --          SH2DMAUReset => SH2DMAUReset,
            SH2DMAURegSource => RegArrayOutA, 
            SH2DMAUImmediateSource => DMAUImmediateSource, 
            SH2DMAURegOffset => RegArrayOutB, 
            SH2DMAUImmediateOffset => DMAUImmediateOffset, 
            SH2DMAUSrcSel => SH2DMAUSrcSel,
            SH2DMAUOffsetSel => SH2DMAUOffsetSel, 
            SH2DMAUIncDecSel  => SH2DMAUIncDecSel, 
            SH2DMAUIncDecBit  => SH2DMAUIncDecBit, 
            SH2DMAUPrePostSel => SH2DMAUPrePostSel, 
            SH2DataAddressBus => SH2DataAddressBus,       -- just GBR?
            SH2DataAddressSrc => SH2DataAddressSrc
        );

    -- Instantiate PMAU
    SH2PMAU : entity  work.SH2PMAU
        port map(
            SH2PMAUReset => SH2PMAUReset,
            SH2PMAURegSource => RegArrayOutA, 
            SH2PMAUImmediateSource => PMAUImmediateSource, 
            SH2PMAURegOffset => RegArrayOutB, 
            SH2PMAUImmediateOffset => PMAUImmediateOffset, 
            SH2PMAUSrcSel => SH2PMAUSrcSel,
            SH2PMAUOffsetSel => SH2PMAUOffsetSel, 
            SH2PMAUIncDecSel  => SH2PMAUIncDecSel, 
            SH2PMAUIncDecBit  => SH2PMAUIncDecBit, 
            SH2PMAUPrePostSel => SH2PMAUPrePostSel, 
            SH2ProgramAddressBus => SH2PC        --make the PC come out into here
            );    
    
    -- ================================================================================================== Finite State Machine
    updatePCandIRandSetNextState: process(SH2clock)
    begin
        --On the rising edge of the CurrentState, perform state-specific tasks
            --ZERO_CLK
                --Stop the PC
                --Fetch the instruction
            --FETCH_IR
                --Update the PC
                --Get next instruction while executing current instruction
            --END_OF_FILE
                --Stop the PC
        if rising_edge(SH2clock) then

            -- Reset reading or writing when clock is high
            WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1'; 
            RE0 <= '1'; RE1 <= '1'; RE2 <= '1'; RE3 <= '1'; 

            -- Update state on rising edge
            case CurrentState is 
                when ZERO_CLK =>
                    ------------------------------------------------ Setting control signals

                    --Setting PMAU control signals
                    SH2PMAUReset            <= PMAU_RESET;
                    SH2PMAUSrcSel           <= DEFAULT_SRC_SEL;
                    PMAUImmediateOffset     <= DEFAULT_OFFSET_VAL;
                    SH2PMAUOffsetSel        <= DEFAULT_OFFSET_SEL;
                    SH2PMAUIncDecSel        <= DEFAULT_DEC_SEL;
                    SH2PMAUIncDecBit        <= DEFAULT_DEC_BIT;
                    SH2PMAUPrePostSel       <= DEFAULT_POST_SEL;

                    ------------------------------------------------ Update state
                    if (Reset = '1') then           -- Reset is active low, so '1' means we're not reset
                        CurrentState <= FETCH_IR;
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT; -- 
                        SH2SelDataBus <= HOLD_DATA_BUS;
                        
                    else 
                        CurrentState <= ZERO_CLK;   -- We are resetting
                        -- Set data, address buses to high impedance so that test bench can write them
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                    end if;

                when FETCH_IR =>


                    ------------------------------------------------ Setting control signals
                    -- Set data, address buses to high impedance so that test bench can write them
                    SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT;
                    SH2SelDataBus <= HOLD_DATA_BUS;

                    --Set clock counter back to 1
                    ClockCounter            <= ONE_CLOCK;
                    
                    --Setting PMAU control signals: Want PMAU to increment
                    SH2PMAUReset            <= PMAU_NO_RESET;
                    SH2PMAUSrcSel           <= DEFAULT_SRC_SEL;
                    -- PMAUImmediateSource  <= ClockCounter;
                    SH2PMAUOffsetSel        <= DEFAULT_NO_OFF_VAL;
                    SH2PMAUIncDecSel        <= DEFAULT_INC_SEL;
                    SH2PMAUIncDecBit        <= DEFAULT_DEC_BIT;
                    SH2PMAUPrePostSel       <= DEFAULT_PRE_SEL;

                    ------------------------------------------------ Set next state
                    if (InstructionReg = "XXXXXXXXXXXXXXXX") then 
                        report "End of file reached.";
                        CurrentState <= END_OF_FILE;
                    else 
                        CurrentState <= FETCH_IR;
                    end if;

                    report "FALLING EDGE OF CLOCK: ";
                    report "IR = " & to_hstring(InstructionReg);
                    report "DataBus = " & to_hstring(SH2DataBus);
                    report "PC = " & to_hstring(SH2PC);
                    report "AddressBus = " & to_hstring(SH2AddressBus);
                    report "=========================";
                    

                when END_OF_FILE =>
                    
                    -------------------------------------------------- Setting control signals

                    SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                    SH2SelDataBus <= OPEN_DATA_BUS;  

                    --Setting PMAU control signals
                    SH2PMAUReset            <= PMAU_RESET;
                    SH2PMAUSrcSel           <= DEFAULT_SRC_SEL;
                    PMAUImmediateOffset     <= DEFAULT_OFFSET_VAL;
                    SH2PMAUOffsetSel        <= DEFAULT_OFFSET_SEL;
                    SH2PMAUIncDecSel        <= DEFAULT_DEC_SEL;
                    SH2PMAUIncDecBit        <= DEFAULT_DEC_BIT;
                    SH2PMAUPrePostSel       <= DEFAULT_POST_SEL;
                    SH2SelDataBus <= OPEN_DATA_BUS;         -- no writing to buses when end of file!
                    SH2SelAddressBus <= OPEN_ADDRESS_BUS;

                    -------------------------------------------------- Update state
                    CurrentState <= END_OF_FILE;

                when others =>
                    --Should not get here
                    --But if it does, do not update the PC
                    SH2PMAUReset            <= PMAU_RESET;
                    SH2PMAUSrcSel           <= DEFAULT_SRC_SEL;
                    PMAUImmediateOffset     <= DEFAULT_OFFSET_VAL;
                    SH2PMAUOffsetSel        <= DEFAULT_OFFSET_SEL;
                    SH2PMAUIncDecSel        <= DEFAULT_DEC_SEL;
                    SH2PMAUIncDecBit        <= DEFAULT_DEC_BIT;
                    SH2PMAUPrePostSel       <= DEFAULT_POST_SEL;

                    --Do nothing
                    InstructionReg          <= NOP;
            end case;

            if (Reset = '0') then 
                CurrentState <= ZERO_CLK;   -- We are resetting
            end if;

        end if;
        --On the falling edge of the clock, update Read and Write for correct RAM interaction based on state
            --ZERO_CLK
                --Read enabled for fetching first instruction
                --Write disabled, busy fetching instruction
            --FETCH_IR
                --Read enabled for fetching next instruction
                --Write disabled, busy fetching next instruction
            --END_OF_FILE
                --Read enabled for RAM dumping
                --Write remains disabled for RAM dumping
        if falling_edge(SH2clock) then
            case CurrentState is
                when ZERO_CLK =>

                    ------------------------------------------------ Load in first instruction
                    --Fetching first instruction (high bytes of DataBus)
                    if (Reset = '1') then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT;
                        SH2SelDataBus <= HOLD_DATA_BUS;
                        WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1';  -- not writing only read high bytes
                        RE0 <= '1'; RE1 <= '1'; RE2 <= '0'; RE3 <= '0';
                        InstructionReg          <= SH2DataBus(regLen-1 downto instrLen) or INSTR_LEN_ZEROS;
                    else 
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                        WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1';  -- no reading or writing
                        RE0 <= '1'; RE1 <= '1'; RE2 <= '1'; RE3 <= '1';
                        InstructionReg          <= (others => 'X') ;
                    end if;

                when FETCH_IR =>

                     ---------------------------------------------------------- Fetch the next instruction
                    
                    if (store_opcode_in_low_byte = '0') then
                        -- Read high bytes in, write disable
                        WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1'; 
                        RE0 <= '1'; RE1 <= '1'; RE2 <= '0'; RE3 <= '0'; 
                        InstructionReg <= SH2DataBus(regLen-1 downto instrLen); 

                        -- next write, write low byte of same address
                        store_opcode_in_low_byte <= '1';

                    else
                        -- Read low bytes in, write disable
                        WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1'; 
                        RE0 <= '0'; RE1 <= '0'; RE2 <= '1'; RE3 <= '1'; 
                        InstructionReg <= SH2DataBus(instrLen-1 downto 0);  

                        -- written low byte so next instruction need to write high byte of new memory location
                        store_opcode_in_low_byte <= '0';

                    end if;

                    -- Now, for the rising edge of the clock, need to hold data bus.
                    SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT;
                    SH2SelDataBus <= HOLD_DATA_BUS;

                    report "FALLING EDGE OF CLOCK: ";
                    report "IR = " & to_hstring(InstructionReg);
                    report "DataBus = " & to_hstring(SH2DataBus);
                    report "PC = " & to_hstring(SH2PC);
                    report "AddressBus = " & to_hstring(SH2AddressBus);
                    report "=========================";
                    
                when others => -- halt the CPU

                    -- Set data, address buses to high impedance so that test bench can write them
                    SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                    SH2SelDataBus <= OPEN_DATA_BUS;

                    -- Do not read, write, or carry out any instructions
                    InstructionReg <= NOP;
                    WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1'; 
                    RE0 <= '1'; RE1 <= '1'; RE2 <= '1'; RE3 <= '1'; 
                    
            end case;
        end if;
    end process updatePCandIRandSetNextState;

    --Update the CurrentState to the NextState every rising edge of the clock
    --Set Read and Write to inactive during the rising edge of the clock
   

    -- ================================================================================================== Instruction Decoding, State Determination
    --combinational if statements
    --Matches the 
    --at the end of the matches -> update the currentstate with nextState variable
    matchInstruction : process(SH2clock)
    begin
        if rising_edge(SH2clock) then
                
            if std_match(ADD_imm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(11 downto 8)));
                
                --Setting ALU control signals
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);
                SH2ALUUseImmediateOperand   <= '0';
                SH2Cin                      <= '0';     --Could probably use "else" case to reassign the default values, as some of these are only set in specific commands
                SH2FCmd                     <= "0000";
                SH2CinCmd                   <= "00";
                SH2SCmd                     <= "000";   --Doesn't matter what this does, not selecting the output
                SH2ALUCmd                   <= "01";          

            elsif std_match(SHLL_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore <= '0';
                SH2RegAxStore <= '0';

                --Setting ALU control signals
                SH2Cin                      <= '0';
                SH2FCmd                     <= "0000";
                SH2CinCmd                   <= "00";
                SH2SCmd                     <= "000";
                SH2ALUCmd                   <= "10";
                
            elsif std_match(AND_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(7 downto 4)));
                SH2RegBSel      <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore <= '0';
                SH2RegAxStore <= '0';

                --Setting ALU control signals
                SH2Cin                      <= '0';
                SH2FCmd                     <= "1000";
                SH2CinCmd                   <= "00";
                SH2SCmd                     <= "000";
                SH2ALUCmd                   <= "00";
            
            elsif std_match(NOP, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegStore <= '0';
                SH2RegAxStore <= '0';

            else
                --Setting Reg Array control signals
                SH2RegStore <= '0';
                SH2RegAxStore <= '0';
            end if;

        end if;
    end process matchInstruction;

    -- Set buses (This is combinational, outside of any clocked process.)
    SH2DataBus <= SH2DataBus when SH2SelDataBus = HOLD_DATA_BUS else
        RegArrayOutA when SH2SelDataBus = SET_DATA_BUS_TO_REG_A_OUT else
        SH2ALUResult when SH2SelDataBus = SET_DATA_BUS_TO_ALU_OUT else
            (others => 'Z');

    SH2AddressBus <= SH2AddressBus when SH2SelAddressBus = HOLD_ADDRESS_BUS else
        SH2DataAddressSrc when SH2SelAddressBus = SET_ADDRESS_BUS_TO_DMAU_OUT else
        SH2PC when SH2SelAddressBus = SET_ADDRESS_BUS_TO_PMAU_OUT else
            (others => 'Z');

end Structural;
