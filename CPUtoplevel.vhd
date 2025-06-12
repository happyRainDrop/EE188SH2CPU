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
--     17 May 25  Nerissa Finnen    Fixed first instruction attempt, redid instruction constants table (3rd time)
--     10 June 25 Ruth Berkun       First program works. Fixed timing (fetch, then execute). 
--                                  Not using RegB for ALU and MOV ops
--                                  Made intermediate variables for MOV reg outputs.
--     11 June 25 Ruth Berkun       Update addressbus to reflect 4*PC value (Each longword is 4 apart in memory address now) 
--     11 June 25 Nerissa Finnen    Updated all Shift commands to new style
--     12 June 25 Ruth Berkun       Implementing MOV commands (load and store)
----------------------------------------------------------------------------

------------------------------------------------- Constants
library ieee;
use ieee.std_logic_1164.ALL;
package SH2_CPU_Constants is

    -- Memory instantiation
    constant memBlockWordSize : integer := 256;  -- memBlockWordSize words in every memory block
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

    -- DMAU and PMAU inc/dec select
    constant MAU_INC_SEL : std_logic := '0';
    constant MAU_DEC_SEL : std_logic := '1';
    constant MAU_PRE_SEL : std_logic := '0';
    constant MAU_POST_SEL : std_logic := '1';

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
    constant NUM_ADDRESS_BUS_OPTIONS : integer := 4; -- DMAU, PMAU, regs, hold, open
    constant OPEN_DATA_BUS : integer := 0;
    constant HOLD_DATA_BUS : integer := 1;
    constant SET_DATA_BUS_TO_REG_A2_OUT : integer := 2;
    constant SET_DATA_BUS_TO_ALU_OUT : integer := 3;
    constant OPEN_ADDRESS_BUS : integer := 0;
    constant HOLD_ADDRESS_BUS : integer := 1;
    constant SET_ADDRESS_BUS_TO_PMAU_OUT : integer := 2;
    constant SET_ADDRESS_BUS_TO_DMAU_OUT : integer := 3;

    -- Holding settings for DMAU and PMAU; ensures that the register 
    -- is held at current value by decrementing by 1 and adding 1 as offset
    constant PMAU_HOLD         : std_logic := '0';     --Holds the PC value in the PMAU
    constant PMAU_NO_HOLD         : std_logic := '1';     --Does not hold the PC value in the PMAU
    constant DMAU_ZERO_IMM      : std_logic_vector(31 downto 0) := (others => '0');
    constant DEFAULT_DEC_SEL    : std_logic := MAU_DEC_SEL;     --Select decrement
    constant DEFAULT_BIT    : integer := 0;         --Only 0th bit to modify
    constant DEFAULT_POST_SEL   : std_logic := MAU_POST_SEL;     --Post decrement so nothing is modified!
    constant DEFAULT_OFFSET_SEL : integer := 4;         --Select immediate offset multiplied by 1
    constant DEFAULT_OFFSET_VAL : std_logic_vector(31 downto 0) := "00000000000000000000000000000001";    --Set the offset to be 1
    constant MAU_ZERO_OFFSET : std_logic_vector(31 downto 0) := (others => '0');

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

    --ALU commands
    --Will fill in more these are gonna take a long time ngl
    constant ALU_USE_IMM    : std_logic := '1';
    constant ALU_NO_IMM     : std_logic := '0';
    --Unsure if these two ^ are right
    constant ALU_CIN        : std_logic := '1';
    constant ALU_NO_CIN     : std_logic := '0';
    constant ALU_FB_SEL     : std_logic_vector(1 downto 0) := "00";
    constant ALU_SHIFT_SEL  : std_logic_vector(1 downto 0) := "10";
    constant ALU_ADDER_SEL  : std_logic_vector(1 downto 0) := "01";

    constant ALU_ZERO_IMM   : std_logic_vector(regLen - 1 downto 0) := "00000000000000000000000000000000";

    --Reg array default values
    constant REG_ZEROTH_SEL : integer := 0;
    constant REG_STORE      : std_logic := '1';
    constant REG_NO_STORE   : std_logic := '0';
    constant STATUS_REG_INDEX   : integer := 17;

    -- ALU default values (not too important; 
    --                     ALU can do whatever it wants so long as it doesn't update address or data bus)
    constant DEFAULT_ALU_CIN : std_logic := '0';     --No Cin
    constant DEFAULT_ALU_F_CMD : std_logic_vector(3 downto 0) := "1010";  --Use OpB for the Adder
    constant DEFAULT_ALU_CIN_CMD : std_logic_vector(1 downto 0) := "00";    --No Cin
    constant DEFAULT_ALU_S_CMD : std_logic_vector(2 downto 0) := "000";   --Doesn't matter the shift (output is not selected from ALU)
    constant DEFAUL_ALU_CMD : std_logic_vector(1 downto 0) := "00";    
    constant DEFAULT_ALU_IMM_OP : std_logic_vector(31 downto 0)  := (others => '0');   --All 0s
    constant DEFAULT_ALU_USE_IMM : std_logic := '0';     --By default, don't use the immediate value

    -- Misc constants
    constant REG_LEN_ZEROES : std_logic_vector(31 downto 0) := (others => '0');
    constant INSTR_LEN_ZEROES : std_logic_vector(15 downto 0) := (others => '0');
    constant WRITE_TO_MEMORY : std_logic := '1';
    constant NO_WRITE_TO_MEMORY : std_logic := '0';
    constant READ_FROM_MEMORY : std_logic := '1';
    constant NO_READ_FROM_MEMORY : std_logic := '0';
    constant WORD_MASK  : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant BYTE_MASK  : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
   

end SH2_CPU_Constants;

library ieee;
use ieee.std_logic_1164.ALL;
package SH2_IR_Constants is
    -- SH-2 Instruction Opcode Constants
    -- Register, immediate, and specified registers
    constant ADD_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1100";
    constant ADD_imm_Rn : std_logic_vector(15 downto 0) := "0111------------";
    constant ADDC_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1110";
    constant ADDV_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1111";
    constant AND_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1001";
    constant AND_imm_R0 : std_logic_vector(15 downto 0) := "11001001--------";
    constant AND_B_imm_GBR : std_logic_vector(15 downto 0) := "11001101--------";
    constant BF_disp : std_logic_vector(15 downto 0) := "10001011--------";
    constant BF_S_disp : std_logic_vector(15 downto 0) := "10001111--------";
    constant BRA_disp : std_logic_vector(15 downto 0) := "1010------------";
    constant BRAF_Rm : std_logic_vector(15 downto 0) := "0000----00100011";
    constant BSR_disp : std_logic_vector(15 downto 0) := "1011------------";
    constant BSRF_Rm : std_logic_vector(15 downto 0) := "0000----00000011";
    constant BT_disp : std_logic_vector(15 downto 0) := "10001001--------";
    constant BT_S_disp : std_logic_vector(15 downto 0) := "10001101--------";
    --constant CLRMAC : std_logic_vector(15 downto 0) := "0000000000101000";
    constant CLRT : std_logic_vector(15 downto 0) := "0000000000001000";
    constant CMP_EQ_imm_R0 : std_logic_vector(15 downto 0) := "10001000--------";
    constant CMP_EQ_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0000";
    constant CMP_GE_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0011";
    constant CMP_GT_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0111";
    constant CMP_HI_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0110";
    constant CMP_HS_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0010";
    constant CMP_PL_Rn : std_logic_vector(15 downto 0) := "0100----00010101";
    constant CMP_PZ_Rn : std_logic_vector(15 downto 0) := "0100----00010001";
    constant CMP_STR_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1100";
    --constant DIV0S_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------0111";
    --constant DIV0U : std_logic_vector(15 downto 0) := "0000000000011001";
    --constant DIV1_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0100";
    --constant DMULS_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1101";
    --constant DMULU_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0101";
    constant DT_Rn : std_logic_vector(15 downto 0) := "0100----00010000";
    constant EXTS_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1110";
    constant EXTS_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1111";
    constant EXTU_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1100";
    constant EXTU_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1101";
    constant JMP_Rm : std_logic_vector(15 downto 0) := "0100----00101011";
    constant JSR_Rm : std_logic_vector(15 downto 0) := "0100----00001011";
    constant LDC_Rm_SR : std_logic_vector(15 downto 0) := "0100----00001110";
    constant LDC_Rm_GBR : std_logic_vector(15 downto 0) := "0100----00011110";
    constant LDC_Rm_VBR : std_logic_vector(15 downto 0) := "0100----00101110";
    constant LDC_L_Rm_SR : std_logic_vector(15 downto 0) := "0100----00000111";
    constant LDC_L_Rm_GBR : std_logic_vector(15 downto 0) := "0100----00010111";
    constant LDC_L_Rm_VBR : std_logic_vector(15 downto 0) := "0100----00100111";
    --constant LDS_Rm_MACH : std_logic_vector(15 downto 0) := "0100----00001010";
    --constant LDS_Rm_MACL : std_logic_vector(15 downto 0) := "0100----00011010";
    constant LDS_Rm_PR : std_logic_vector(15 downto 0) := "0100----00101010";
    --constant LDS_L_Rm_MACH : std_logic_vector(15 downto 0) := "0100----00000110";
    --constant LDS_L_Rm_MACL : std_logic_vector(15 downto 0) := "0100----00010110";
    constant LDS_L_Rm_PR : std_logic_vector(15 downto 0) := "0100----00100110";
    --constant MAC_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000--------1111";
    --constant MAC_W_Rm_Rn : std_logic_vector(15 downto 0) := "0100--------1111";
    constant MOV_IMM_TO_Rn        : std_logic_vector(15 downto 0) := "1110------------"; -- MOV #imm, Rn
    constant MOV_W_PC_DISP_TO_Rn  : std_logic_vector(15 downto 0) := "1001------------"; -- MOV.W @(disp,PC), Rn
    constant MOV_L_PC_DISP_TO_Rn  : std_logic_vector(15 downto 0) := "1101------------"; -- MOV.L @(disp,PC), Rn
    constant MOV_Rm_TO_Rn         : std_logic_vector(15 downto 0) := "0110--------0011"; -- MOV Rm, Rn
    constant MOVA_PC_R0 : std_logic_vector(15 downto 0) := "11000111--------";           -- MOVA @(disp,PC),R0
    constant MOVT_Rn : std_logic_vector(15 downto 0) := "0000----00101001";              -- MOVT Rn
    constant MOVB_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110--------0000"; -- MOV.B @Rm, Rn
    constant MOVW_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110--------0001"; -- MOV.W @Rm, Rn
    constant MOVL_atRm_TO_Rn      : std_logic_vector(15 downto 0) := "0110--------0010"; -- MOV.L @Rm, Rn
    constant MOVB_atR0Rm_TO_Rn    : std_logic_vector(15 downto 0) := "0000--------1100"; -- MOV.B @(R0,Rm),Rn
    constant MOVW_atR0Rm_TO_Rn    : std_logic_vector(15 downto 0) := "0000--------1101"; -- MOV.W @(R0,Rm),Rn  
    constant MOVL_atR0Rm_TO_Rn    : std_logic_vector(15 downto 0) := "0000--------1110";    -- MOV.L @(R0,Rm),Rn
    constant MOVB_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110--------0100"; -- MOV.B @Rm+, Rn
    constant MOVW_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110--------0101"; -- MOV.W @Rm+, Rn
    constant MOVL_atPostIncRm_TO_Rn : std_logic_vector(15 downto 0) := "0110--------0110"; -- MOV.L @Rm+, Rn
    constant MOVB_atDispRm_TO_R0  : std_logic_vector(15 downto 0) := "10000100--------"; -- MOV.B @(disp,Rm), R0
    constant MOVW_atDispRm_TO_R0  : std_logic_vector(15 downto 0) := "10000101--------"; -- MOV.W @(disp,Rm), R0
    constant MOVL_atDispRm_TO_Rn  : std_logic_vector(15 downto 0) := "0101------------"; -- MOV.L @(disp,Rm), Rn
    constant MOV_B_R0_GBR : std_logic_vector(15 downto 0) := "11000100--------";         -- MOV.B @(disp,GBR), R0
    constant MOV_W_R0_GBR : std_logic_vector(15 downto 0) := "11000101--------";         -- MOV.W @(disp,GBR), R0
    constant MOV_L_R0_GBR : std_logic_vector(15 downto 0) := "11000110--------";         -- MOV.L @(disp,GBR), R0
    constant MOVB_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010--------0000"; -- MOV.B Rm, @Rn
    constant MOVW_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010--------0001"; -- MOV.W Rm, @Rn
    constant MOVL_Rm_TO_atRn      : std_logic_vector(15 downto 0) := "0010--------0010"; -- MOV.L Rm, @Rn
    constant MOVB_Rm_TO_atR0Rn    : std_logic_vector(15 downto 0) := "0000--------0100"; -- MOV.B Rm, @(R0,Rn)
    constant MOVW_Rm_TO_atR0Rn    : std_logic_vector(15 downto 0) := "0000--------0101"; -- MOV.W Rm, @(R0,Rn)  
    constant MOVL_Rm_TO_atR0Rn : std_logic_vector(15 downto 0) := "0000--------0110";    -- MOV.L Rm, @(R0,Rn)
    constant MOVB_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010--------0100"; -- MOV.B Rm, @–Rn
    constant MOVW_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010--------0101"; -- MOV.W Rm, @–Rn
    constant MOVL_Rm_TO_atPreDecRn : std_logic_vector(15 downto 0) := "0010--------0110"; -- MOV.L Rm, @–Rn
    constant MOVB_R0_TO_atDispRn  : std_logic_vector(15 downto 0) := "10000000--------"; -- MOV.B R0, @(disp,Rn)
    constant MOVW_R0_TO_atDispRn  : std_logic_vector(15 downto 0) := "10000001--------"; -- MOV.W R0, @(disp,Rn)
    constant MOVL_Rm_TO_atDispRn  : std_logic_vector(15 downto 0) := "0001------------"; -- MOV.L Rm, @(disp,Rn)
    constant MOV_B_GBR_R0 : std_logic_vector(15 downto 0) := "11000000--------"; -- MOV.B R0, @(disp,GBR)
    constant MOV_W_GBR_R0 : std_logic_vector(15 downto 0) := "11000001--------"; -- MOV.W R0, @(disp,GBR)
    constant MOV_L_GBR_R0 : std_logic_vector(15 downto 0) := "11000010--------"; -- MOV.L R0, @(disp,GBR)
    --constant MUL_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000--------0111";
    --constant MULS_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1111";
    --constant MULU_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1110";
    constant NEG_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1011";
    constant NEGC_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1010";
    constant NOP : std_logic_vector(15 downto 0) := "0000000000001001";
    constant NOT_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------0111";
    constant OR_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1011";
    constant OR_imm_R0 : std_logic_vector(15 downto 0) := "11001011--------";
    constant OR_B_imm_GBR : std_logic_vector(15 downto 0) := "11001111--------";
    constant ROTCL_Rn : std_logic_vector(15 downto 0) := "0100----00100100";
    constant ROTCR_Rn : std_logic_vector(15 downto 0) := "0100----00100101";
    constant ROTL_Rn : std_logic_vector(15 downto 0) := "0100----00000100";
    constant ROTR_Rn : std_logic_vector(15 downto 0) := "0100----00000101";
    constant RTE : std_logic_vector(15 downto 0) := "0000000000101011";
    constant RTS : std_logic_vector(15 downto 0) := "0000000000001011";
    constant SETT : std_logic_vector(15 downto 0) := "0000000000011000";
    constant SHAL_Rn : std_logic_vector(15 downto 0) := "0100----00100000";
    constant SHAR_Rn : std_logic_vector(15 downto 0) := "0100----00100001";
    constant SHLL_Rn : std_logic_vector(15 downto 0) := "0100----00000000";
    constant SHLR_Rn : std_logic_vector(15 downto 0) := "0100----00000001";
    --constant SHLL2_Rn : std_logic_vector(15 downto 0) := "0100----00001000";
    --constant SHLR2_Rn : std_logic_vector(15 downto 0) := "0100----00001001";
    --constant SHLL8_Rn : std_logic_vector(15 downto 0) := "0100----00011000";
    --constant SHLR8_Rn : std_logic_vector(15 downto 0) := "0100----00011001";
    --constant SHLL16_Rn : std_logic_vector(15 downto 0) := "0100----00101000";
    --constant SHLR16_Rn : std_logic_vector(15 downto 0) := "0100----00101001";
    constant SLEEP : std_logic_vector(15 downto 0) := "0000000000011011";
    constant STC_SR_Rn : std_logic_vector(15 downto 0) := "0000----00000010";
    constant STC_GBR_Rn : std_logic_vector(15 downto 0) := "0000----00010010";
    constant STC_VBR_Rn : std_logic_vector(15 downto 0) := "0000----00100010";
    constant STC_L_SR_Rn : std_logic_vector(15 downto 0) := "0100----00000011";
    constant STC_L_GBR_Rn : std_logic_vector(15 downto 0) := "0100----00010011";
    constant STC_L_VBR_Rn : std_logic_vector(15 downto 0) := "0100----00100011";
    --constant STS_MACH_Rn : std_logic_vector(15 downto 0) := "0000----00001010";
    --constant STS_MACL_Rn : std_logic_vector(15 downto 0) := "0000----00011010";
    constant STS_PR_Rn : std_logic_vector(15 downto 0) := "0000----00101010";
    --constant STS_L_MACH_Rn : std_logic_vector(15 downto 0) := "0100----00000010";
    --constant STS_L_MACL_Rn : std_logic_vector(15 downto 0) := "0100----00010010";
    constant STS_L_PR_Rn : std_logic_vector(15 downto 0) := "0100----00100010";
    constant SUB_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1000";
    constant SUBC_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1010";
    constant SUBV_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1011";
    constant SWAP_B_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1000"; -- SWAP.B Rm,Rn
    constant SWAP_W_Rm_Rn : std_logic_vector(15 downto 0) := "0110--------1001"; -- SWAP.W Rm,Rn
    constant TAS_B_Rn : std_logic_vector(15 downto 0) := "0100----00011011";
    constant TRAPA_imm : std_logic_vector(15 downto 0) := "11000011--------";
    constant TST_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1000";
    constant TST_imm_R0 : std_logic_vector(15 downto 0) := "11001000--------";
    constant TST_B_imm_GBR : std_logic_vector(15 downto 0) := "11001100--------";
    constant XTRCT_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1101"; -- XTRCT Rm,Rn
    constant XOR_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1010";
    constant XOR_imm_R0 : std_logic_vector(15 downto 0) := "11001010--------";
    constant XOR_B_imm_GBR : std_logic_vector(15 downto 0) := "11001110--------";
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
    signal SH2Cin      : std_logic := '0';                                        -- Loads in the carry in bit
    signal SH2CinCmd   : std_logic_vector(1 downto 0) := (others => '0');         -- carry in operation
    signal SH2SCmd     : std_logic_vector(2 downto 0) := (others => '0');         -- shift operation
    signal SH2ALUCmd   : std_logic_vector(1 downto 0) := (others => '0');         -- ALU result select
    -- ALU additional from control line inputs (not directly from generic ALU)
    signal SH2ALUImmediateOperand      : std_logic_vector(regLen-1 downto 0) := (others => '0'); -- control unit should pad it (with 1s or 0s
                                                                                                -- based on whether it's signed or not)
                                                                                                -- before giving us immediate operand
    signal SH2ALUUseImmediateOperand   : std_logic; -- 1 for use immediate operand, 0 otherwise
    signal SH2ALUOpAImmediate      : std_logic_vector(regLen-1 downto 0) := (others => '0'); -- control unit should pad it (with 1s or 0s
    -- based on whether it's signed or not)
    -- before giving us immediate operand
    signal SH2ALUOpAUseImmediateOperand   : std_logic; -- 1 for use immediate operand, 0 otherwise
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
    signal SH2CalculatedDataAddress: std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- DMAU output address
    signal HoldCalculatedDataAddress: std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- save DMAU output address
                                                                                                  -- for write on next clock
    signal SH2DataAddressSrc : std_logic_vector(regLen - 1 downto 0) := (others => '0');   -- DMAU input address, updated
                                                                                        -- (Need control line to see which src)

        -- Read and Write flags that the PMAU sets
    signal WriteToMemoryB : std_logic := NO_WRITE_TO_MEMORY;  -- active high
    signal WriteToMemoryW : std_logic := NO_WRITE_TO_MEMORY;  
    signal WriteToMemoryL : std_logic := NO_WRITE_TO_MEMORY; 
    signal ReadFromMemoryB : std_logic := NO_WRITE_TO_MEMORY; -- active high
    signal ReadFromMemoryW : std_logic := NO_WRITE_TO_MEMORY;  
    signal ReadFromMemoryL : std_logic := NO_WRITE_TO_MEMORY; 

    -------------------------------------------------------------------------------------
    -- PMAU FROM CONTROL LINE INPUTS
    signal SH2PMAUHold      : std_logic := '0';
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

    signal HoldRegA : std_logic_vector(regLen - 1 downto 0) := (others => '0');
    signal HoldRegA2 : std_logic_vector(regLen - 1 downto 0) := (others => '0');

    signal SH2PC : std_logic_vector(regLen - 1 downto 0) := (others => '0'); -- the PC: a very special register!
    signal SH2PC_next : std_logic_vector(regLen - 1 downto 0) := (others => '0'); -- what to set PC to on next rising edge of clock
    ------------------------------------------------------------------------------------------

    -- Signals and states
    --==================================================================================================================================================
    -- CPU top level signals; finite state machine and IR
    type states is (ZERO_CLK,  FETCH_IR, END_OF_FILE); 
    --TWO_CLK_W, TWO_CLK_R, THREE_CLK_R, THREE_CLK_W);
    signal CurrentState     : states;

    signal InstructionReg   : std_logic_vector(instrLen - 1 downto 0) := (others => 'Z'); -- IR
    signal PrevIR : std_logic_vector(instrLen - 1 downto 0) := (others => 'Z'); -- IR
    signal ClockCounter     : std_logic_vector(regLen - 1 downto 0); -- what clock cycle are we on?

    signal SignExtend : std_logic_vector(regLen - 1 downto 0);

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
            SH2ALUOpB   => RegArrayOutA2,              -- to be output from the register array (if they so exist)
            SH2ALUImmediateOperand => SH2ALUImmediateOperand,           -- can also be immediate (in instruction)
            SH2ALUOpAImmediate => SH2ALUOpAImmediate,
            SH2ALUOpAUseImmediateOperand => SH2ALUOPAUseImmediateOperand,
            SH2ALUUseImmediateOperand => SH2ALUUseImmediateOperand, 
            SH2Cin      =>  SH2Cin, -- Cin comes from T bit of SR, which is the rightmost bit                    
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
            SH2DMAURegSource => RegArrayOutA, 
            SH2DMAUImmediateSource => DMAUImmediateSource, 
            SH2DMAURegOffset => RegArrayOutB, 
            SH2DMAUImmediateOffset => DMAUImmediateOffset, 
            SH2DMAUSrcSel => SH2DMAUSrcSel,
            SH2DMAUOffsetSel => SH2DMAUOffsetSel, 
            SH2DMAUIncDecSel  => SH2DMAUIncDecSel, 
            SH2DMAUIncDecBit  => SH2DMAUIncDecBit, 
            SH2DMAUPrePostSel => SH2DMAUPrePostSel, 
            SH2DataAddressBus => SH2CalculatedDataAddress,       -- just GBR?
            SH2DataAddressSrc => SH2DataAddressSrc
        );

    -- Instantiate PMAU
    SH2PMAU : entity  work.SH2PMAU
        port map(
            SH2PMAUHold => SH2PMAUHold,
            SH2PC => SH2PC,
            SH2PMAURegSource => RegArrayOutA, 
            SH2PMAUImmediateSource => PMAUImmediateSource, 
            SH2PMAURegOffset => RegArrayOutB, 
            SH2PMAUImmediateOffset => PMAUImmediateOffset, 
            SH2PMAUSrcSel => SH2PMAUSrcSel,
            SH2PMAUOffsetSel => SH2PMAUOffsetSel, 
            SH2PMAUIncDecSel  => SH2PMAUIncDecSel, 
            SH2PMAUIncDecBit  => SH2PMAUIncDecBit, 
            SH2PMAUPrePostSel => SH2PMAUPrePostSel, 
            SH2ProgramAddressBus => SH2PC_next        --make the PC come out into here
            );    
    
    -- ================================================================================================== Finite State Machine
    updatePCandIRandSetNextState: process(SH2clock)
        --========================================================== Procedures
        procedure holdPC is
        begin
            SH2PMAUHold            <= PMAU_HOLD;
            SH2PMAUSrcSel           <= PMAU_SRC_SEL_PC;
            PMAUImmediateOffset     <= DEFAULT_OFFSET_VAL;
            SH2PMAUOffsetSel        <= DEFAULT_OFFSET_SEL;
            SH2PMAUIncDecSel        <= DEFAULT_DEC_SEL;
            SH2PMAUIncDecBit        <= DEFAULT_BIT;
            SH2PMAUPrePostSel       <= DEFAULT_POST_SEL; 
        end procedure;

        procedure incPC is 
        begin
            SH2PMAUHold            <= PMAU_NO_HOLD;
            SH2PMAUSrcSel           <= PMAU_SRC_SEL_PC;
            SH2PMAUOffsetSel        <= DEFAULT_NO_OFF_VAL;
            SH2PMAUIncDecSel        <= DEFAULT_INC_SEL;
            SH2PMAUIncDecBit        <= DEFAULT_BIT;
            SH2PMAUPrePostSel       <= DEFAULT_PRE_SEL;
            SH2PC <= SH2PC_next; 
        end procedure;

        procedure disableReadWrite is
        begin
            WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1'; 
            RE0 <= '1'; RE1 <= '1'; RE2 <= '1'; RE3 <= '1';
        end procedure;

        variable addressIndex : integer range 3 downto 0 := 0;

    begin

        -- Rising edge: Update state, load PC, load IR
        --=====================================================================================
        if rising_edge(SH2clock) then

           disableReadWrite;

            -- Update state on rising edge
            case CurrentState is 
                when ZERO_CLK =>
                    
                    holdPC;
                    ------------------------------------------------ Update state
                    if (Reset = '1') then 
                        CurrentState <= FETCH_IR;    -- CPU is enabled for the first time
                        -- For the next state: prepare to load in the first instruction. Data bus needs to be high-Z.
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT; 
                        SH2SelDataBus <= HOLD_DATA_BUS;
                    else 
                        CurrentState <= ZERO_CLK;                      -- CPU is still in reset mode (off)
                        -- For the next state: Set data, address buses to high impedance so that test bench can write them
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                    end if;
                when FETCH_IR => 

                    -------------------------------------------------- Update the IR, clock cycle, and PC

                    RE0 <= '0'; RE1 <= '0'; RE2 <= '1'; RE3 <= '1';  -- Read low bytes in (instructions stored in low bytes)
                    ClockCounter            <= ONE_CLOCK;       --Set clock counter back to 1
                    incPC;

                    ------------------------------------------------ Set next state
                    if (InstructionReg = "XXXXXXXXXXXXXXXX") then 
                        report "End of file reached.";
                        CurrentState <= END_OF_FILE;

                        -- For the next state: Set data, address buses to high impedance so that test bench can write them
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= HOLD_DATA_BUS;

                    else 
                        CurrentState <= FETCH_IR;

                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT; -- Open data bus for next read-in of codespace
                        SH2SelDataBus <= OPEN_DATA_BUS;

                    end if;
                    
                when others =>  -- End of File or invalid state
                    
                    holdPC;
                    CurrentState <= END_OF_FILE;
                    InstructionReg <= NOP;

                    -- For the next state: prepare to load in the first instruction. Data bus needs to be high-Z
                    SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                    SH2SelDataBus <= OPEN_DATA_BUS; 

            end case;

            if (Reset = '0') then 
                CurrentState <= ZERO_CLK;   -- We are resetting
            end if;

        end if;

        -- Falling edge: Update select address and data bus signals (after they were set by InstrMatch on rising edge)
        --=====================================================================================
        if falling_edge(SH2clock) then

            disableReadWrite;

            -- Calculate for byte/word reads and writes (Only ever uses the DMAU output address)
            addressIndex := to_integer(unsigned(HoldCalculatedDataAddress(1 downto 0))); 

            -- Update select address and data bus signals
            case CurrentState is
                when ZERO_CLK =>
                    -- nothing to do

                when FETCH_IR =>
                    
                    -- Figure out which bits to write to RAM
                     -- assume address, data bus correctly set in instruction matching
                    if (WriteToMemoryB = WRITE_TO_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT; 
                        
                        case addressIndex is
                            when 0 =>
                                WE3 <= '0'; WE2 <= '1'; WE1 <= '1'; WE0 <= '1';
                            when 1 =>
                                WE3 <= '1'; WE2 <= '0'; WE1 <= '1'; WE0 <= '1';
                            when 2 =>
                                WE3 <= '1'; WE2 <= '1'; WE1 <= '0'; WE0 <= '1';
                            when 3 =>
                                WE3 <= '1'; WE2 <= '1'; WE1 <= '1'; WE0 <= '0';
                            when others =>
                                WE3 <= '1'; WE2 <= '1'; WE1 <= '1'; WE0 <= '1';
                            end case;

                    elsif (WriteToMemoryW = WRITE_TO_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT;

                        case addressIndex is
                            when 0 =>
                                WE3 <= '0'; WE2 <= '0'; WE1 <= '1'; WE0 <= '1';
                            when 1 =>
                                WE3 <= '1'; WE2 <= '0'; WE1 <= '0'; WE0 <= '1';
                            when 2 =>
                                WE3 <= '1'; WE2 <= '1'; WE1 <= '0'; WE0 <= '0';
                            when others =>
                                WE3 <= '1'; WE2 <= '1'; WE1 <= '1'; WE0 <= '1';
                            end case;


                    elsif (WriteToMemoryL = WRITE_TO_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT;
                        WE0 <= '0'; WE1 <= '0'; WE2 <= '0'; WE3 <= '0';     -- write the whole longword

                    end if;

                    -- Figure out which bits to load from RAM
                     -- assume address, data bus correctly set in instruction matching
                    if (ReadFromMemoryB = READ_FROM_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;

                        case addressIndex is
                            when 0 =>
                                RE3 <= '0'; RE2 <= '1'; RE1 <= '1'; RE0 <= '1';
                            when 1 =>
                                RE3 <= '1'; RE2 <= '0'; RE1 <= '1'; RE0 <= '1';
                            when 2 =>
                                RE3 <= '1'; RE2 <= '1'; RE1 <= '0'; RE0 <= '1';
                            when 3 =>
                                RE3 <= '1'; RE2 <= '1'; RE1 <= '1'; RE0 <= '0';
                            when others =>
                                RE3 <= '1'; RE2 <= '1'; RE1 <= '1'; RE0 <= '1';
                        end case;

                    elsif (ReadFromMemoryW = READ_FROM_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;

                        case addressIndex is
                            when 0 =>
                                RE3 <= '0'; RE2 <= '0'; RE1 <= '1'; RE0 <= '1';
                            when 1 =>
                                RE3 <= '1'; RE2 <= '0'; RE1 <= '0'; RE0 <= '1';
                            when 2 =>
                                RE3 <= '1'; RE2 <= '1'; RE1 <= '0'; RE0 <= '0';
                            when others =>
                                RE3 <= '1'; RE2 <= '1'; RE1 <= '1'; RE0 <= '1';
                            end case;

                    elsif (ReadFromMemoryL = READ_FROM_MEMORY) then
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                        RE0 <= '0'; RE1 <= '0'; RE2 <= '0'; RE3 <= '0';  -- assume address, data bus correctly set in instruction matching
                    end if;
                    
                when others => -- halt the CPU
                    InstructionReg <= NOP;
                    
            end case;
        end if;
    end process updatePCandIRandSetNextState;

    --Update the CurrentState to the NextState every rising edge of the clock
    --Set Read and Write to inactive during the rising edge of the clock
   

    -- ================================================================================================== Instruction Decoding, State Determination
    --combinational if statements
    --Matches the 
    --at the end of the matches -> update the currentstate with nextState variable
    matchInstruction : process(InstructionReg)
                        
        -- Set default instruction-specific control signals
        -- Does not include PMAU and address/data bus setting logic, because that is determined
        -- by the state machine
        
        --Temproary variable to help with the subtractions with carrys
        variable SubCarryBus    : std_logic_vector(regLen-1 downto 0) := (others => '0');

        procedure SetDefaultControlSignals is
        begin
            -- Default RegArray inputs: Do not input any registers, 
            -- only put Reg0 on output buses 

            -- Default ALU inputs. Immediate is 0 and not used by default. Carry ins are also 0
            SH2Cin                    <= DEFAULT_ALU_CIN;
            SH2FCmd                   <= DEFAULT_ALU_F_CMD;
            SH2CinCmd                 <= DEFAULT_ALU_CIN_CMD;
            SH2SCmd                   <= DEFAULT_ALU_S_CMD;
            SH2ALUCmd                 <= DEFAUL_ALU_CMD;
            SH2ALUImmediateOperand    <= DEFAULT_ALU_IMM_OP;
            SH2ALUUseImmediateOperand <= DEFAULT_ALU_USE_IMM;
            SH2ALUOpAUseImmediateOperand <= DEFAULT_ALU_USE_IMM;
            SH2ALUOpAImmediate        <= DEFAULT_ALU_IMM_OP;

            -- Default DMAU inputs
            SH2DMAUSrcSel       <= DMAU_SRC_SEL_IMM;
            SH2DMAUOffsetSel    <= DEFAULT_OFFSET_SEL;
            SH2DMAUIncDecSel    <= DEFAULT_DEC_SEL;
            SH2DMAUIncDecBit    <= DEFAULT_BIT;
            SH2DMAUPrePostSel   <= DEFAULT_POST_SEL;
            DMAUImmediateSource <= DMAU_ZERO_IMM;
            DMAUImmediateOffset <= MAU_ZERO_OFFSET;

        end procedure;

    begin

        if CurrentState = FETCH_IR then
            --Default all the units
            SetDefaultControlSignals;

            --  ==================================================================================================
            -- ARITHMETIC
            -- ==================================================================================================
            if std_match(InstructionReg, ADD_imm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 

                --Setting ALU control signals
                SH2FCmd                     <= "1010";  --Use OpB for the Adder
                SH2ALUCmd                   <= "01";    --Select the Adder Output
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);   --Select the immediate value from the IR
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;     --Use the immediate value
            
            elsif std_match(InstructionReg, ADD_Rm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd                     <= "1010";  --Use OpB for the Adder
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, ADDC_Rm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2RegA1Sel                 <= REG_SR;  --Grab the status register to get the T bit
                SH2Cin                      <= RegArrayOutA1(0);    --Load in the T-bit as Cin
                SH2CinCmd                   <= "10";    --Set the Cin Adder command to take in Cin
                SH2FCmd                     <= "1010";  --Use OpB for the Adder
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, ADDV_Rm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel                 <= REG_SR;  --Grab the status register to get the T bit

                --Setting ALU control signals
                SH2FCmd                     <= "1010";  --Use OpB for the Adder
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, SUB_Rm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd                     <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, SUBC_Rm_Rn) then
                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel                 <= REG_SR;  --Grab the status register to get the T bit

                --Setting ALU control signals
                --To do: Rn - Rm - T => Rn - (Rm + T)
                SubCarryBus := std_logic_vector(to_unsigned(
                    to_integer(unsigned(RegArrayOutA2)) +
                    to_integer(unsigned(std_logic_vector'("0" & RegArrayOutA1(0)))),
                    RegArrayOutA2'length));

                SH2ALUImmediateOperand       <= SubCarryBus;
                SH2ALUUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value for OpB

                SH2FCmd                     <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                   <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, SUBV_Rm_Rn) then

                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel                 <= REG_SR;  --Grab the status register to get the T bit

                --Setting ALU control signals
                SH2FCmd                     <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, NEG_Rm_Rn) then
                -- Setting register ops for ALU
                SH2ALUOpAImmediate              <= DEFAULT_ALU_IMM_OP;
                SH2ALUOpAUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd                  <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                <= "01";    --Select the Adder Output    
            
            elsif std_match(InstructionReg, NEGC_Rm_Rn) then
                -- Setting register ops for ALU
                SH2ALUOpAImmediate              <= DEFAULT_ALU_IMM_OP;
                SH2ALUOpAUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel                 <= REG_SR;  --Grab the status register to get the T bit

                --Setting ALU control signals
                --To do: 0 - Rm - T => 0 - (Rm + T)
                SubCarryBus := std_logic_vector(to_unsigned(
                    to_integer(unsigned(RegArrayOutA2)) +
                    to_integer(unsigned(std_logic_vector'("0" & RegArrayOutA1(0)))),
                    RegArrayOutA2'length));

                SH2ALUImmediateOperand       <= SubCarryBus;
                SH2ALUUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value for OpB

                SH2FCmd                     <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                   <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                   <= "01";    --Select the Adder Output

            elsif std_match(InstructionReg, EXTS_B_Rm_Rn) then    
                
            elsif std_match(InstructionReg, EXTS_W_Rm_Rn) then  

            elsif std_match(InstructionReg, EXTU_B_Rm_Rn) then  
                SH2ALUOpAImmediate              <= BYTE_MASK;
                SH2ALUOpAUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(InstructionReg, EXTU_W_Rm_Rn) then  
                SH2ALUOpAImmediate              <= WORD_MASK;
                SH2ALUOpAUseImmediateOperand    <= ALU_USE_IMM;     --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));    --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(InstructionReg, DT_Rn) then  
                -- Setting register ops for ALU
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn 
                SH2ALUImmediateOperand <= "00000000000000000000000000000001";
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;     --Use the immediate value
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd                     <= "0101";  --Use not OpB for the Adder
                SH2CinCmd                   <= "01";    --Use the 1 option into the Adder
                                                        --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd                   <= "01";    --Select the Adder Output
                                
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  
            elsif std_match(InstructionReg, CMP_EQ_imm_R0) then  


            --  ==================================================================================================
            -- SHIFTS (0/8) : Needs testing
            --  ==================================================================================================
            elsif std_match(SHLL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn  
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting

                --Setting ALU control signals
                SH2SCmd                     <= "000";   --Left shift left
                SH2ALUCmd                   <= "10";    --Select the shifter output

            elsif std_match(SHLR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn   
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting                                 

                --Setting ALU control signals
                SH2SCmd                     <= "100";   --LSR
                SH2ALUCmd                   <= "10";    --Select the shifter output
            
            elsif std_match(SHAR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn    
                SH2RegA2Sel  <= REG_SR;                                             --Grab the status register for Shifting
        
                --Setting ALU control signals
                SH2SCmd                     <= "101";   --ASR
                SH2ALUCmd                   <= "10";    --Select the shifter output
        
            elsif std_match(SHAL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn  
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting                    

                --Setting ALU control signals
                SH2SCmd                     <= "000";   --LSL
                SH2ALUCmd                   <= "10";    --Select the shifter output
            
            elsif std_match(ROTCR_Rn, InstructionReg) then
                -- Setting Reg Array control signals                         
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting

                --Setting ALU control signals
                SH2Cin                      <= RegArrayOutA2(0); --Feed in T-bit into RRC
                SH2SCmd                     <= "111";   --RRC
                SH2ALUCmd                   <= "10";    --Select the shifter output

            elsif std_match(ROTCL_Rn, InstructionReg) then
                -- Setting Reg Array control signals                                
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting
               
                --Setting ALU control signals
                SH2Cin                      <= RegArrayOutA2(0); --Feed in T-bit into RLC
                SH2SCmd                     <= "011";   --Left shift left
                SH2ALUCmd                   <= "10";    --Select the shifter output
            
            elsif std_match(ROTR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting
               
                --Setting ALU control signals
                SH2SCmd                     <= "110";   --ROR
                SH2ALUCmd                   <= "10";    --Select the shifter output

            elsif std_match(ROTL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegASel  <= to_integer(unsigned(InstructionReg(11 downto 8)));   --OpA of ALU comes out of RegArray at Rn     
                SH2RegA2Sel  <= REG_SR;                                                  --Grab the status register for Shifting                             

                --Setting ALU control signals
                SH2SCmd                     <= "010";   --ROL
                SH2ALUCmd                   <= "10";    --Select the shifter output

            --  ==================================================================================================
            -- LOGICAL 0/9 Needs testing
            --  ==================================================================================================
            elsif std_match(AND_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(7 downto 4)));
                SH2RegA2Sel      <= to_integer(unsigned(InstructionReg(11 downto 8)));

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(AND_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel  <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(TST_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(7 downto 4)));
                SH2RegA2Sel      <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegA1Sel         <= REG_SR;

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(TST_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel  <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;
                SH2RegA1Sel         <= REG_SR;

                --Setting ALU control signals
                SH2FCmd                     <= "1000";
                SH2ALUCmd                   <= ALU_FB_SEL;    

            elsif std_match(OR_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(7 downto 4)));
                SH2RegA2Sel      <= to_integer(unsigned(InstructionReg(11 downto 8)));

                --Setting ALU control signals
                SH2FCmd                     <= "1110";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(OR_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel  <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd                     <= "1110";
                SH2ALUCmd                   <= ALU_FB_SEL;
        
            elsif std_match(XOR_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(7 downto 4)));
                SH2RegA2Sel      <= to_integer(unsigned(InstructionReg(11 downto 8)));

                --Setting ALU control signals
                SH2FCmd                     <= "0110";
                SH2ALUCmd                   <= ALU_FB_SEL;

            elsif std_match(XOR_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel  <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand      <= (23 downto 0 => '0') & InstructionReg(7 downto 0);
                SH2ALUUseImmediateOperand   <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd                     <= "0110";
                SH2ALUCmd                   <= ALU_FB_SEL;       
                
            elsif std_match(NOT_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegASel      <= to_integer(unsigned(InstructionReg(11 downto 8)));

                --Setting ALU control signals
                SH2FCmd                     <= "0011";
                SH2ALUCmd                   <= ALU_FB_SEL; 
            
            --  ==================================================================================================
            -- LOAD
            --  ==================================================================================================
            -- Load immediate
            elsif std_match(MOV_IMM_TO_Rn, InstructionReg) then
                -- Nothing to precalculate here. We'll do the loading in the execute stage.

            -- Load from reg address directly
            elsif std_match(MOVB_atRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atRm_TO_Rn, InstructionReg) then
            
            elsif std_match(MOVL_atRm_TO_Rn, InstructionReg) then
                 -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 downto 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
            
            -- Load from reg address + reg address in R0
            elsif std_match(MOVB_atR0Rm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atR0Rm_TO_Rn, InstructionReg) then

            elsif std_match(MOVL_atR0Rm_TO_Rn, InstructionReg) then

            -- Load from reg address post-incremented
            elsif std_match(MOVB_atPostIncRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atPostIncRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVL_atPostIncRm_TO_Rn, InstructionReg) then

            -- Load from disp * (1,2,4) + reg address (into R0 or Rn)
            elsif std_match(MOVB_atDispRm_TO_R0, InstructionReg) then

            elsif std_match(MOVW_atDispRm_TO_R0, InstructionReg) then

            elsif std_match(MOVL_atDispRm_TO_Rn, InstructionReg) then

            -- Load from dis * (1,2,4) + GBR (into R0)
            elsif std_match(MOV_B_R0_GBR, InstructionReg) then

            elsif std_match(MOV_W_R0_GBR, InstructionReg) then

            elsif std_match(MOV_L_R0_GBR, InstructionReg) then

            --  ==================================================================================================
            -- STORE
            --  ==================================================================================================

            -- Store value in Rm to RAM address in Rn
            elsif std_match(MOVB_Rm_TO_atRn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

            elsif std_match(MOVW_Rm_TO_atRn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

            elsif std_match(MOVL_Rm_TO_atRn, InstructionReg) then

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
            
            -- Store value in Rm to (RAM address in Rn + RAM address in R0)
            elsif std_match(MOVB_Rm_TO_atR0Rn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0;                                                  -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

            elsif std_match(MOVW_Rm_TO_atR0Rn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0;                                                  -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

            elsif std_match(MOVL_Rm_TO_atR0Rn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0;                                                  -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

            -- Store value in Rm to (pre decremented RAM address in Rn)
            elsif std_match(MOVB_Rm_TO_atPreDecRn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

            elsif std_match(MOVW_Rm_TO_atPreDecRn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

            elsif std_match(MOVL_Rm_TO_atPreDecRn, InstructionReg) then
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

            -- Store value in Rm to ((RAM address in Rn) + (1,2,4)*disp)
            elsif std_match(MOVB_R0_TO_atDispRn, InstructionReg) then

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= std_logic_vector(resize(unsigned(InstructionReg(3 downto 0)), regLen)); -- zero-padded immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1;

            elsif std_match(MOVW_R0_TO_atDispRn, InstructionReg) then

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= std_logic_vector(resize(unsigned(InstructionReg(3 downto 0)), regLen)); -- zero-padded immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x2;

            elsif std_match(MOVL_Rm_TO_atDispRn, InstructionReg) then

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 downto 4)));   -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= std_logic_vector(resize(unsigned(InstructionReg(3 downto 0)), regLen)); -- zero-padded immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x4;

            -- Store value in R0 to ((RAM address in Rn) + (1,2,4)*GBR)
            elsif std_match(MOV_B_GBR_R0, InstructionReg) then

            elsif std_match(MOV_W_GBR_R0, InstructionReg) then

            elsif std_match(MOV_L_GBR_R0, InstructionReg) then

            --  ==================================================================================================
            -- SYSTEM CONTROL
            --  ==================================================================================================
            elsif std_match(NOP, InstructionReg) then

                SetDefaultControlSignals;

            elsif std_match(SETT, InstructionReg) then

            else
                -- report "Warning: The following instruction register did not match any known instructions: Value = x""" & to_hstring(InstructionReg) & """";

                SetDefaultControlSignals;
                
            end if;

        end if;
    end process matchInstruction;


    executeInstruction : process(SH2Clock)
            -- Set default instruction-specific control signals
        -- Does not include PMAU and address/data bus setting logic, because that is determined
        -- by the state machine

        variable FlagUpdate    : std_logic_vector(regLen-1 downto 0) := (others => '0');
        variable addressIndexInternal : integer range 3 downto 0 := 0;

        procedure SetDefaultExecuteSignals is
        begin
            -- Default RegArray inputs: Do not input any registers, 
            SH2RegIn <= REG_LEN_ZEROES; 
            SH2RegInSel <= REG_ZEROTH_SEL; 
            SH2RegStore <= REG_NO_STORE;   
                                 
            SH2RegAxIn  <= REG_LEN_ZEROES;
            SH2RegAxInSel <= REG_ZEROTH_SEL;
            SH2RegAxStore <= REG_NO_STORE; 

            -- Reset reads and writes;
            WriteToMemoryB <= NO_WRITE_TO_MEMORY;
            WriteToMemoryW <= NO_WRITE_TO_MEMORY;
            WriteToMemoryL <= NO_WRITE_TO_MEMORY;
            ReadFromMemoryB <= NO_READ_FROM_MEMORY;
            ReadFromMemoryW <= NO_READ_FROM_MEMORY;
            ReadFromMemoryL <= NO_READ_FROM_MEMORY;

        end procedure;

        -- Make sure low byte of Rm is put in the place where we memory will be reading it from!
        -- recall, stores read the value to store from HoldRegA2, so we'll modify that
        procedure WriteBUpdateHoldRegA2Val is
        begin
            case addressIndexInternal is
                when 0 => -- Store in highest byte
                    HoldRegA2(31 downto 24) <= RegArrayOutA2(7 downto 0);
                when 1 => -- Store in second highest byte
                    HoldRegA2(23 downto 16) <= RegArrayOutA2(7 downto 0);
                when 2 => -- Store in second lowest byte
                    HoldRegA2(15 downto 8) <= RegArrayOutA2(7 downto 0);
                when 3 => -- Store in lowest byte
                    HoldRegA2(7 downto 0) <= RegArrayOutA2(7 downto 0);
                when others =>
                    -- should never get here
                end case;
        end procedure;

        -- Make sure low word of Rm is put in the place where we memory will be reading it from!
        -- recall, stores read the value to store from HoldRegA2, so we'll modify that
        procedure WriteWUpdateHoldRegA2Val is
        begin
            -- Make sure low byte of Rm is put in the place where we memory will be reading it from!
            -- recall, stores read the value to store from HoldRegA2, so we'll modify that
            case addressIndexInternal is
                when 0 => -- Store starting from highest byte
                    HoldRegA2(31 downto 16) <= RegArrayOutA2(15 downto 0);
                when 1 => -- Store starting from second highest byte
                    HoldRegA2(23 downto 8) <= RegArrayOutA2(15 downto 0);
                when 2 => -- Store starting from second lowest byte
                    HoldRegA2(15 downto 0) <= RegArrayOutA2(15 downto 0);
                when others =>
                    -- should never get here
            end case;
        end procedure;

    begin


        if CurrentState = FETCH_IR and rising_edge(SH2Clock) then

            SetDefaultExecuteSignals;

            -- Save the values of the registers for execute state, which is a clock after the instruction
            HoldRegA2 <= RegArrayOutA2;
            HoldCalculatedDataAddress <= SH2CalculatedDataAddress;
            addressIndexInternal := to_integer(unsigned(SH2CalculatedDataAddress(1 downto 0)));

            --  ==================================================================================================
            -- ARITHMETIC
            -- ==================================================================================================
            if std_match(InstructionReg, ADD_imm_Rn) then

                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 
            
            elsif std_match(InstructionReg, ADD_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 

            elsif std_match(InstructionReg, ADDC_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 

                FlagUpdate := RegArrayOutA1;

                FlagUpdate(0) := not FlagBus(FLAG_INDEX_CARRYOUT);                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  

            elsif std_match(InstructionReg, ADDV_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 

                FlagUpdate := RegArrayOutA1;

                FlagUpdate(0) := not FlagBus(FLAG_INDEX_OVERFLOW);                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value                                 --Actually write 

            elsif std_match(InstructionReg, SUB_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 

            elsif std_match(InstructionReg, SUBC_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 
                
                FlagUpdate := RegArrayOutA1;

                FlagUpdate(0) := not FlagBus(FLAG_INDEX_CARRYOUT);                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value                                         --Actually write 

            elsif std_match(InstructionReg, SUBV_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write 

                FlagUpdate := RegArrayOutA1;

                FlagUpdate(0) := not FlagBus(FLAG_INDEX_OVERFLOW);                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value                                            --Actually write 

            elsif std_match(InstructionReg, NEG_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Update the value    
                

            elsif std_match(InstructionReg, NEGC_Rm_Rn) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Update the value
                
                FlagUpdate := RegArrayOutA1;

                FlagUpdate(0) := not FlagBus(FLAG_INDEX_CARRYOUT);                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value   

            elsif std_match(InstructionReg, EXTU_B_Rm_Rn) then  
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;     
        
            elsif std_match(InstructionReg, EXTU_W_Rm_Rn) then  
                
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;     

            elsif std_match(InstructionReg, EXTS_B_Rm_Rn) then  
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;     
        
            elsif std_match(InstructionReg, EXTS_W_Rm_Rn) then  
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;     
            
            elsif std_match(InstructionReg, DT_Rn) then
                if std_match(SH2ALUResult, ALU_ZERO_IMM) then
                    SH2RegIn <= RegArrayOutA1(regLen - 1 downto 1) & '1';
                    SH2RegInSel <= REG_SR;
                    SH2RegStore <= REG_STORE;       
                else
                    SH2RegIn <= RegArrayOutA1(regLen - 1 downto 1) & '0';
                    SH2RegInSel <= REG_SR;
                    SH2RegStore <= REG_STORE;     
                end if;
            

            --  ==================================================================================================
            -- SHIFTS (0/8) : Needs testing
            --  ==================================================================================================
            elsif std_match(SHLL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(regLen - 1);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  
                
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

            elsif std_match(SHLR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(0);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  
            
            elsif std_match(SHAR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(0);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  

            elsif std_match(SHAL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(regLen - 1);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  
        
            elsif std_match(ROTCL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write
                
                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(regLen - 1);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value                                          --Update the value   

            elsif std_match(ROTCR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(0);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  

            elsif std_match(ROTL_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write
               
                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(regLen - 1);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value               
            
            elsif std_match(ROTR_Rn, InstructionReg) then
                -- Setting Reg Array control signals
                SH2RegIn <= SH2ALUResult;                                           --Set what data needs to be written
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));   --Set the register to write to (Rn)
                SH2RegStore <= REG_STORE;                                           --Actually write

                FlagUpdate := RegArrayOutA2;

                FlagUpdate(0) :=  RegArrayOutA(0);                         --Update the T-bit with the high bit value of Rn  
                SH2RegAxIn  <= FlagUpdate;                                       --Write back in Ax which is the Status Register   
                SH2RegAxInSel <= REG_SR;                                            --Write back at the Status Register index
                SH2RegAxStore <= REG_STORE;                                         --Update the value  
            
            --  ==================================================================================================
            -- LOGICAL 0/9 Needs testing
            --  ==================================================================================================
            elsif std_match(AND_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn        <= SH2ALUResult;
                SH2RegInSel     <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore     <= REG_STORE;
            
            elsif std_match(AND_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn    <= SH2ALUResult;
                SH2RegInSel <= REG_ZEROTH_SEL;
                SH2RegStore <= REG_STORE;
            
            elsif std_match(TST_Rm_Rn, InstructionReg) then    
                if std_match(SH2ALUResult, REG_LEN_ZEROES) then 
                    FlagUpdate := RegArrayOutA1;
                    FlagUpdate(0) := '1';                   --Load into Status Register the new Carryout
                    SH2RegAxIn  <= FlagUpdate;              --Write back in Ax which is the Status Register 
                    SH2RegAxInSel       <= REG_SR;
                    SH2RegAxStore       <= REG_STORE;
                end if;

            elsif std_match(TST_imm_R0, InstructionReg) then
                if std_match(SH2ALUResult, REG_LEN_ZEROES) then 
                FlagUpdate := RegArrayOutA1;
                FlagUpdate(0) := '1';                   --Load into Status Register the new Carryout
                SH2RegAxIn  <= FlagUpdate;              --Write back in Ax which is the Status Register 
                SH2RegAxInSel       <= REG_SR;
                SH2RegAxStore       <= REG_STORE;
                end if;

            elsif std_match(OR_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn        <= SH2ALUResult;
                SH2RegInSel     <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore     <= REG_STORE;

            elsif std_match(OR_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn    <= SH2ALUResult;
                SH2RegInSel <= REG_ZEROTH_SEL;
                SH2RegStore <= REG_STORE;

            elsif std_match(XOR_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn        <= SH2ALUResult;
                SH2RegInSel     <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore     <= REG_STORE;

            elsif std_match(XOR_imm_R0, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn    <= SH2ALUResult;
                SH2RegInSel <= REG_ZEROTH_SEL;
                SH2RegStore <= REG_STORE;
           
            elsif std_match(NOT_Rm_Rn, InstructionReg) then
                --Setting Reg Array control signals
                SH2RegIn        <= SH2ALUResult;
                SH2RegInSel     <= to_integer(unsigned(InstructionReg(11 downto 8)));
                SH2RegStore     <= REG_STORE;

            --  ==================================================================================================
            -- LOAD
            --  ==================================================================================================

            -- Load immediate
            elsif std_match(MOV_IMM_TO_Rn, InstructionReg) then
                
                -- Store immediate data into Rn
                SH2RegIn <= std_logic_vector(resize(signed(InstructionReg(7 downto 0)), regLen)); -- sign-extended immediate
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Store inside register Rn (at index n)
                SH2RegStore <= REG_STORE;

            -- Load from reg address directly
            elsif std_match(MOVB_atRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVL_atRm_TO_Rn, InstructionReg) then

                -- Store data bus data into Rn
                SH2RegIn <= SH2DataBus;
                SH2RegInSel <= to_integer(unsigned(InstructionReg(11 downto 8)));  -- Store inside register Rn (at index n)
                SH2RegStore <= REG_STORE;
                
                ReadFromMemoryL <= READ_FROM_MEMORY;
            
            -- Load from reg address + reg address in R0
            elsif std_match(MOVB_atR0Rm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atR0Rm_TO_Rn, InstructionReg) then

            elsif std_match(MOVL_atR0Rm_TO_Rn, InstructionReg) then

            -- Load from reg address post-incremented
            elsif std_match(MOVB_atPostIncRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVW_atPostIncRm_TO_Rn, InstructionReg) then

            elsif std_match(MOVL_atPostIncRm_TO_Rn, InstructionReg) then

            -- Load from disp * (1,2,4) + reg address (into R0 or Rn)
            elsif std_match(MOVB_atDispRm_TO_R0, InstructionReg) then

            elsif std_match(MOVW_atDispRm_TO_R0, InstructionReg) then

            elsif std_match(MOVL_atDispRm_TO_Rn, InstructionReg) then

            -- Load from dis * (1,2,4) + GBR (into R0)
            elsif std_match(MOV_B_R0_GBR, InstructionReg) then

            elsif std_match(MOV_W_R0_GBR, InstructionReg) then

            elsif std_match(MOV_L_R0_GBR, InstructionReg) then

            --  ==================================================================================================
            -- STORE
            --  ==================================================================================================

             -- Store value in Rm to RAM address in Rn
            elsif std_match(MOVB_Rm_TO_atRn, InstructionReg) then

                WriteBUpdateHoldRegA2Val; 
                WriteToMemoryB <= WRITE_TO_MEMORY;

            elsif std_match(MOVW_Rm_TO_atRn, InstructionReg) then
                
                WriteWUpdateHoldRegA2Val;
                WriteToMemoryW <= WRITE_TO_MEMORY;

            elsif std_match(MOVL_Rm_TO_atRn, InstructionReg) then
                WriteToMemoryL <= WRITE_TO_MEMORY;
            
            -- Store value in Rm to (RAM address in Rn + RAM address in R0)
            elsif std_match(MOVB_Rm_TO_atR0Rn, InstructionReg) then
                
                WriteBUpdateHoldRegA2Val;
                WriteToMemoryB <= WRITE_TO_MEMORY;

            elsif std_match(MOVW_Rm_TO_atR0Rn, InstructionReg) then
                
                WriteWUpdateHoldRegA2Val;
                WriteToMemoryW <= WRITE_TO_MEMORY;

            elsif std_match(MOVL_Rm_TO_atR0Rn, InstructionReg) then
                WriteToMemoryL <= WRITE_TO_MEMORY;

            -- Store value in Rm to (pre decremented RAM address in Rn)
            elsif std_match(MOVB_Rm_TO_atPreDecRn, InstructionReg) then

                WriteBUpdateHoldRegA2Val;
                WriteToMemoryB <= WRITE_TO_MEMORY;

            elsif std_match(MOVW_Rm_TO_atPreDecRn, InstructionReg) then

                WriteWUpdateHoldRegA2Val;
                WriteToMemoryW <= WRITE_TO_MEMORY;

            elsif std_match(MOVL_Rm_TO_atPreDecRn, InstructionReg) then

                WriteToMemoryL <= WRITE_TO_MEMORY;

            -- Store value in R0 to ((RAM address in Rn) + (1,2,4)*disp)
            elsif std_match(MOVB_R0_TO_atDispRn, InstructionReg) then

                WriteBUpdateHoldRegA2Val;
                WriteToMemoryB <= WRITE_TO_MEMORY;

            elsif std_match(MOVW_R0_TO_atDispRn, InstructionReg) then

                WriteWUpdateHoldRegA2Val;
                WriteToMemoryW <= WRITE_TO_MEMORY;

            elsif std_match(MOVL_Rm_TO_atDispRn, InstructionReg) then

                WriteToMemoryL <= WRITE_TO_MEMORY;

            -- Store value in R0 to ((RAM address in Rn) + (1,2,4)*GBR)
            elsif std_match(MOV_B_GBR_R0, InstructionReg) then

                WriteBUpdateHoldRegA2Val;
                WriteToMemoryB <= WRITE_TO_MEMORY;

            elsif std_match(MOV_W_GBR_R0, InstructionReg) then

                WriteWUpdateHoldRegA2Val;
                WriteToMemoryW <= WRITE_TO_MEMORY;

            elsif std_match(MOV_L_GBR_R0, InstructionReg) then

                WriteToMemoryL <= WRITE_TO_MEMORY;
            
            end if;

        end if;
    end process executeInstruction;


    -- Set buses (This is combinational, outside of any clocked process.)
    SH2DataBus <= SH2DataBus when SH2SelDataBus = HOLD_DATA_BUS else
        HoldRegA2 when SH2SelDataBus = SET_DATA_BUS_TO_REG_A2_OUT else
        SH2ALUResult when SH2SelDataBus = SET_DATA_BUS_TO_ALU_OUT else
            (others => 'Z');

    -- Note: We multiply the PC by 4 because each 32 memory block is 4 addresses apart
    SH2AddressBus <= SH2AddressBus when SH2SelAddressBus = HOLD_ADDRESS_BUS else
        HoldCalculatedDataAddress when SH2SelAddressBus = SET_ADDRESS_BUS_TO_DMAU_OUT else
    std_logic_vector(to_unsigned(4 * to_integer(unsigned(SH2PC)), SH2AddressBus'length)) when SH2SelAddressBus = SET_ADDRESS_BUS_TO_PMAU_OUT else
            (others => 'Z');


    -- Make instruction reg combinational so that it updates immediately
    InstructionReg <= SH2DataBus(instrLen-1 downto 0) 
                    when SH2Clock = '1'
                    else InstructionReg;


end Structural;