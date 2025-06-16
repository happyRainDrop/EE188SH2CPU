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
--     12 June 25 Ruth Berkun       JMP working and tested, also put GBR and VBR back into RegArray
--     15 June 25 Ruth Berkun       Add LDS.L and STC.L (Pipeline halt logic)
----------------------------------------------------------------------------

------------------------------------------------- Constants
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
PACKAGE SH2_CPU_Constants IS

    -- Memory instantiation
    CONSTANT memBlockWordSize : INTEGER := 256; -- memBlockWordSize words in every memory block
    CONSTANT instrLen : INTEGER := 16;

    -- Register and word size configuration
    CONSTANT regLen : INTEGER := 32; -- Each register is 32 bits
    CONSTANT regCount : INTEGER := 20; -- 16 general + 4 special registers (PR, SR, GBR, VBR)

    -- DMAU configuration
    CONSTANT dmauSourceCount : INTEGER := 4; -- from reg array, GBR, VBR, or immediate
    CONSTANT dmauOffsetCount : INTEGER := 7; -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    CONSTANT maxIncDecBitDMAU : INTEGER := 3; -- Allow inc/dec up to bit 3 (+-4) 

    -- DMAU source select
    CONSTANT DMAU_SRC_SEL_GBR : INTEGER := 0;
    CONSTANT DMAU_SRC_SEL_VBR : INTEGER := 1;
    CONSTANT DMAU_SRC_SEL_REG : INTEGER := 2;
    CONSTANT DMAU_SRC_SEL_IMM : INTEGER := 3;

    -- DMAU offset select
    CONSTANT DMAU_OFFSET_SEL_ZEROES : INTEGER := 0;
    CONSTANT DMAU_OFFSET_SEL_REG_OFFSET_x1 : INTEGER := 1;
    CONSTANT DMAU_OFFSET_SEL_REG_OFFSET_x2 : INTEGER := 2;
    CONSTANT DMAU_OFFSET_SEL_REG_OFFSET_x4 : INTEGER := 3;
    CONSTANT DMAU_OFFSET_SEL_IMM_OFFSET_x1 : INTEGER := 4;
    CONSTANT DMAU_OFFSET_SEL_IMM_OFFSET_x2 : INTEGER := 5;
    CONSTANT DMAU_OFFSET_SEL_IMM_OFFSET_x4 : INTEGER := 6;

    -- DMAU and PMAU inc/dec select
    CONSTANT MAU_INC_SEL : STD_LOGIC := '0';
    CONSTANT MAU_DEC_SEL : STD_LOGIC := '1';
    CONSTANT MAU_PRE_SEL : STD_LOGIC := '0';
    CONSTANT MAU_POST_SEL : STD_LOGIC := '1';

    -- PMAU configuration
    CONSTANT pmauSourceCount : INTEGER := 3; -- from reg array, PC, or immediate
    CONSTANT pmauOffsetCount : INTEGER := 7; -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    CONSTANT maxIncDecBitPMAU : INTEGER := 3; -- Allow inc/dec up to bit 3 (+-4)

    -- PMAU source select
    CONSTANT PMAU_SRC_SEL_PC : INTEGER := 0;
    CONSTANT PMAU_SRC_SEL_REG : INTEGER := 1;
    CONSTANT PMAU_SRC_SEL_IMM : INTEGER := 2;
    CONSTANT PMAU_SRC_SEL_PR : INTEGER := 3;

    -- PMAU offset select
    CONSTANT PMAU_OFFSET_SEL_ZEROES : INTEGER := 0;
    CONSTANT PMAU_OFFSET_SEL_REG_OFFSET_x1 : INTEGER := 1;
    CONSTANT PMAU_OFFSET_SEL_REG_OFFSET_x2 : INTEGER := 2;
    CONSTANT PMAU_OFFSET_SEL_REG_OFFSET_x4 : INTEGER := 3;
    CONSTANT PMAU_OFFSET_SEL_IMM_OFFSET_x1 : INTEGER := 4;
    CONSTANT PMAU_OFFSET_SEL_IMM_OFFSET_x2 : INTEGER := 5;
    CONSTANT PMAU_OFFSET_SEL_IMM_OFFSET_x4 : INTEGER := 6;

    -- Flag bit positions (useful for flag bus indexing)
    CONSTANT FLAG_INDEX_CARRYOUT : INTEGER := 4;
    CONSTANT FLAG_INDEX_HALF_CARRY : INTEGER := 3;
    CONSTANT FLAG_INDEX_OVERFLOW : INTEGER := 2;
    CONSTANT FLAG_INDEX_ZERO : INTEGER := 1;
    CONSTANT FLAG_INDEX_SIGN : INTEGER := 0;

    -- Special register indices
    CONSTANT REG_PR : INTEGER := 16;
    CONSTANT REG_SR : INTEGER := 17;
    CONSTANT REG_GBR : INTEGER := 18;
    CONSTANT REG_VBR : INTEGER := 19;

    -- Choosing data and address bus indicies
    CONSTANT NUM_DATA_BUS_OPTIONS : INTEGER := 3; -- ALU, regs, hold, open
    CONSTANT NUM_ADDRESS_BUS_OPTIONS : INTEGER := 4; -- DMAU, PMAU, regs, hold, open
    CONSTANT OPEN_DATA_BUS : INTEGER := 0;
    CONSTANT HOLD_DATA_BUS : INTEGER := 1;
    CONSTANT SET_DATA_BUS_TO_REG_A2_OUT : INTEGER := 2;
    CONSTANT SET_DATA_BUS_TO_ALU_OUT : INTEGER := 3;
    CONSTANT OPEN_ADDRESS_BUS : INTEGER := 0;
    CONSTANT HOLD_ADDRESS_BUS : INTEGER := 1;
    CONSTANT SET_ADDRESS_BUS_TO_PMAU_OUT : INTEGER := 2;
    CONSTANT SET_ADDRESS_BUS_TO_DMAU_OUT : INTEGER := 3;

    -- Holding settings for DMAU and PMAU; ensures that the register 
    -- is held at current value by decrementing by 1 and adding 1 as offset
    CONSTANT PMAU_HOLD : STD_LOGIC := '0'; --Holds the PC value in the PMAU
    CONSTANT PMAU_NO_HOLD : STD_LOGIC := '1'; --Does not hold the PC value in the PMAU
    CONSTANT DMAU_ZERO_IMM : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    CONSTANT DEFAULT_DEC_SEL : STD_LOGIC := MAU_DEC_SEL; --Select decrement
    CONSTANT DEFAULT_BIT : INTEGER := 0; --Only 0th bit to modify
    CONSTANT DEFAULT_POST_SEL : STD_LOGIC := MAU_POST_SEL; --Post decrement so nothing is modified!
    CONSTANT DEFAULT_OFFSET_SEL : INTEGER := 4; --Select immediate offset multiplied by 1
    CONSTANT DEFAULT_OFFSET_VAL : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000001"; --Set the offset to be 1
    CONSTANT MAU_ZERO_OFFSET : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

    -- Incrementing in PMAU
    CONSTANT DEFAULT_PRE_SEL : STD_LOGIC := MAU_PRE_SEL;
    CONSTANT DEFAULT_INC_SEL : STD_LOGIC := MAU_INC_SEL;
    CONSTANT DEFAULT_NO_OFF_VAL : INTEGER := 0;

    -- Incrementing in DMAU

    -- PC clock increments
    CONSTANT ONE_CLOCK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000001";
    CONSTANT TWO_CLOCK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000010";
    CONSTANT THREE_CLOCK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000011";
    CONSTANT FOUR_CLOCK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000000000100";

    --ALU commands
    --Will fill in more these are gonna take a long time ngl
    CONSTANT ALU_USE_IMM : STD_LOGIC := '1';
    CONSTANT ALU_NO_IMM : STD_LOGIC := '0';
    --Unsure if these two ^ are right
    CONSTANT ALU_CIN : STD_LOGIC := '1';
    CONSTANT ALU_NO_CIN : STD_LOGIC := '0';
    CONSTANT ALU_FB_SEL : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    CONSTANT ALU_SHIFT_SEL : STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";
    CONSTANT ALU_ADDER_SEL : STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";

    CONSTANT ALU_ZERO_IMM : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := "00000000000000000000000000000000";

    --Reg array default values
    CONSTANT REG_ZEROTH_SEL : INTEGER := 0;
    CONSTANT REG_STORE : STD_LOGIC := '1';
    CONSTANT REG_NO_STORE : STD_LOGIC := '0';
    CONSTANT STATUS_REG_INDEX : INTEGER := 17;

    -- ALU default values (not too important; 
    --                     ALU can do whatever it wants so long as it doesn't update address or data bus)
    CONSTANT DEFAULT_ALU_CIN : STD_LOGIC := '0'; --No Cin
    CONSTANT DEFAULT_ALU_F_CMD : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1010"; --Use OpB for the Adder
    CONSTANT DEFAULT_ALU_CIN_CMD : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00"; --No Cin
    CONSTANT DEFAULT_ALU_S_CMD : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000"; --Doesn't matter the shift (output is not selected from ALU)
    CONSTANT DEFAUL_ALU_CMD : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
    CONSTANT DEFAULT_ALU_IMM_OP : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0'); --All 0s
    CONSTANT DEFAULT_ALU_USE_IMM : STD_LOGIC := '0'; --By default, don't use the immediate value

    -- Misc constants
    CONSTANT REG_LEN_ZEROES : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    CONSTANT INSTR_LEN_ZEROES : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    CONSTANT WRITE_TO_MEMORY : STD_LOGIC := '1';
    CONSTANT NO_WRITE_TO_MEMORY : STD_LOGIC := '0';
    CONSTANT READ_FROM_MEMORY : STD_LOGIC := '1';
    CONSTANT NO_READ_FROM_MEMORY : STD_LOGIC := '0';
    CONSTANT WORD_MASK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000000011111111";
    CONSTANT BYTE_MASK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000001111111111111111";
    CONSTANT SR_MASK : STD_LOGIC_VECTOR(31 DOWNTO 0) := "00000000000000000000001111110011";
END SH2_CPU_Constants;

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
PACKAGE SH2_IR_Constants IS
    -- SH-2 Instruction Opcode Constants
    -- Register, immediate, and specified registers
    CONSTANT ADD_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1100";
    CONSTANT ADD_imm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0111------------";
    CONSTANT ADDC_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1110";
    CONSTANT ADDV_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1111";
    CONSTANT AND_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1001";
    CONSTANT AND_imm_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001001--------";
    CONSTANT AND_B_imm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001101--------";
    CONSTANT BF_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10001011--------";
    CONSTANT BF_S_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10001111--------";
    CONSTANT BRA_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "1010------------";
    CONSTANT BRAF_Rm : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00100011";
    CONSTANT BSR_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "1011------------";
    CONSTANT BSRF_Rm : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00000011";
    CONSTANT BT_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10001001--------";
    CONSTANT BT_S_disp : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10001101--------";
    --constant CLRMAC : std_logic_vector(15 downto 0) := "0000000000101000";
    CONSTANT CLRT : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000001000";
    CONSTANT CMP_EQ_imm_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10001000--------";
    CONSTANT CMP_EQ_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------0000";
    CONSTANT CMP_GE_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------0011";
    CONSTANT CMP_GT_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------0111";
    CONSTANT CMP_HI_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------0110";
    CONSTANT CMP_HS_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------0010";
    CONSTANT CMP_PL_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00010101";
    CONSTANT CMP_PZ_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00010001";
    CONSTANT CMP_STR_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1100";
    --constant DIV0S_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------0111";
    --constant DIV0U : std_logic_vector(15 downto 0) := "0000000000011001";
    --constant DIV1_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0100";
    --constant DMULS_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------1101";
    --constant DMULU_L_Rm_Rn : std_logic_vector(15 downto 0) := "0011--------0101";
    CONSTANT DT_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00010000";
    CONSTANT EXTS_B_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1110";
    CONSTANT EXTS_W_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1111";
    CONSTANT EXTU_B_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1100";
    CONSTANT EXTU_W_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1101";
    CONSTANT JMP_Rm : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00101011";
    CONSTANT JSR_Rm : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00001011";
    CONSTANT LDC_Rm_SR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00001110";
    CONSTANT LDC_Rm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00011110";
    CONSTANT LDC_Rm_VBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00101110";
    CONSTANT LDC_L_Rm_SR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000111";
    CONSTANT LDC_L_Rm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00010111";
    CONSTANT LDC_L_Rm_VBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100111";
    --constant LDS_Rm_MACH : std_logic_vector(15 downto 0) := "0100----00001010";
    --constant LDS_Rm_MACL : std_logic_vector(15 downto 0) := "0100----00011010";
    CONSTANT LDS_Rm_PR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00101010";
    --constant LDS_L_Rm_MACH : std_logic_vector(15 downto 0) := "0100----00000110";
    --constant LDS_L_Rm_MACL : std_logic_vector(15 downto 0) := "0100----00010110";
    CONSTANT LDS_L_Rm_PR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100110";
    --constant MAC_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000--------1111";
    --constant MAC_W_Rm_Rn : std_logic_vector(15 downto 0) := "0100--------1111";
    CONSTANT MOV_IMM_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "1110------------"; -- MOV #imm, Rn
    CONSTANT MOV_W_PC_DISP_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "1001------------"; -- MOV.W @(disp,PC), Rn
    CONSTANT MOV_L_PC_DISP_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "1101------------"; -- MOV.L @(disp,PC), Rn
    CONSTANT MOV_Rm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0011"; -- MOV Rm, Rn
    CONSTANT MOVA_PC_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000111--------";           -- MOVA @(disp,PC),R0
    CONSTANT MOVT_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00101001";              -- MOVT Rn
    CONSTANT MOVB_atRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0000"; -- MOV.B @Rm, Rn
    CONSTANT MOVW_atRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0001"; -- MOV.W @Rm, Rn
    CONSTANT MOVL_atRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0010"; -- MOV.L @Rm, Rn
    CONSTANT MOVB_atR0Rm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------1100"; -- MOV.B @(R0,Rm),Rn
    CONSTANT MOVW_atR0Rm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------1101"; -- MOV.W @(R0,Rm),Rn  
    CONSTANT MOVL_atR0Rm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------1110";    -- MOV.L @(R0,Rm),Rn
    CONSTANT MOVB_atPostIncRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0100"; -- MOV.B @Rm+, Rn
    CONSTANT MOVW_atPostIncRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0101"; -- MOV.W @Rm+, Rn
    CONSTANT MOVL_atPostIncRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0110"; -- MOV.L @Rm+, Rn
    CONSTANT MOVB_atDispRm_TO_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10000100--------"; -- MOV.B @(disp,Rm), R0
    CONSTANT MOVW_atDispRm_TO_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10000101--------"; -- MOV.W @(disp,Rm), R0
    CONSTANT MOVL_atDispRm_TO_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0101------------"; -- MOV.L @(disp,Rm), Rn
    CONSTANT MOV_B_R0_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000100--------";         -- MOV.B @(disp,GBR), R0
    CONSTANT MOV_W_R0_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000101--------";         -- MOV.W @(disp,GBR), R0
    CONSTANT MOV_L_R0_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000110--------";         -- MOV.L @(disp,GBR), R0
    CONSTANT MOVB_Rm_TO_atRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0000"; -- MOV.B Rm, @Rn
    CONSTANT MOVW_Rm_TO_atRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0001"; -- MOV.W Rm, @Rn
    CONSTANT MOVL_Rm_TO_atRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0010"; -- MOV.L Rm, @Rn
    CONSTANT MOVB_Rm_TO_atR0Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------0100"; -- MOV.B Rm, @(R0,Rn)
    CONSTANT MOVW_Rm_TO_atR0Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------0101"; -- MOV.W Rm, @(R0,Rn)  
    CONSTANT MOVL_Rm_TO_atR0Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000--------0110";    -- MOV.L Rm, @(R0,Rn)
    CONSTANT MOVB_Rm_TO_atPreDecRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0100"; -- MOV.B Rm, @–Rn
    CONSTANT MOVW_Rm_TO_atPreDecRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0101"; -- MOV.W Rm, @–Rn
    CONSTANT MOVL_Rm_TO_atPreDecRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------0110"; -- MOV.L Rm, @–Rn
    CONSTANT MOVB_R0_TO_atDispRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10000000--------"; -- MOV.B R0, @(disp,Rn)
    CONSTANT MOVW_R0_TO_atDispRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "10000001--------"; -- MOV.W R0, @(disp,Rn)
    CONSTANT MOVL_Rm_TO_atDispRn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0001------------"; -- MOV.L Rm, @(disp,Rn)
    CONSTANT MOV_B_GBR_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000000--------"; -- MOV.B R0, @(disp,GBR)
    CONSTANT MOV_W_GBR_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000001--------"; -- MOV.W R0, @(disp,GBR)
    CONSTANT MOV_L_GBR_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000010--------"; -- MOV.L R0, @(disp,GBR)
    --constant MUL_L_Rm_Rn : std_logic_vector(15 downto 0) := "0000--------0111";
    --constant MULS_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1111";
    --constant MULU_W_Rm_Rn : std_logic_vector(15 downto 0) := "0010--------1110";
    CONSTANT NEG_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1011";
    CONSTANT NEGC_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1010";
    CONSTANT NOP : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000001001";
    CONSTANT NOT_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------0111";
    CONSTANT OR_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1011";
    CONSTANT OR_imm_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001011--------";
    CONSTANT OR_B_imm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001111--------";
    CONSTANT ROTCL_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100100";
    CONSTANT ROTCR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100101";
    CONSTANT ROTL_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000100";
    CONSTANT ROTR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000101";
    CONSTANT RTE : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000101011";
    CONSTANT RTS : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000001011";
    CONSTANT SETT : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000011000";
    CONSTANT SHAL_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100000";
    CONSTANT SHAR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100001";
    CONSTANT SHLL_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000000";
    CONSTANT SHLR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000001";
    --constant SHLL2_Rn : std_logic_vector(15 downto 0) := "0100----00001000";
    --constant SHLR2_Rn : std_logic_vector(15 downto 0) := "0100----00001001";
    --constant SHLL8_Rn : std_logic_vector(15 downto 0) := "0100----00011000";
    --constant SHLR8_Rn : std_logic_vector(15 downto 0) := "0100----00011001";
    --constant SHLL16_Rn : std_logic_vector(15 downto 0) := "0100----00101000";
    --constant SHLR16_Rn : std_logic_vector(15 downto 0) := "0100----00101001";
    CONSTANT SLEEP : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000000000011011";
    CONSTANT STC_SR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00000010";
    CONSTANT STC_GBR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00010010";
    CONSTANT STC_VBR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00100010";
    CONSTANT STC_L_SR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00000011";
    CONSTANT STC_L_GBR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00010011";
    CONSTANT STC_L_VBR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100011";
    --constant STS_MACH_Rn : std_logic_vector(15 downto 0) := "0000----00001010";
    --constant STS_MACL_Rn : std_logic_vector(15 downto 0) := "0000----00011010";
    CONSTANT STS_PR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0000----00101010";
    --constant STS_L_MACH_Rn : std_logic_vector(15 downto 0) := "0100----00000010";
    --constant STS_L_MACL_Rn : std_logic_vector(15 downto 0) := "0100----00010010";
    CONSTANT STS_L_PR_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00100010";
    CONSTANT SUB_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1000";
    CONSTANT SUBC_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1010";
    CONSTANT SUBV_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0011--------1011";
    CONSTANT SWAP_B_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1000"; -- SWAP.B Rm,Rn
    CONSTANT SWAP_W_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0110--------1001"; -- SWAP.W Rm,Rn
    CONSTANT TAS_B_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0100----00011011";
    CONSTANT TRAPA_imm : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11000011--------";
    CONSTANT TST_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1000";
    CONSTANT TST_imm_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001000--------";
    CONSTANT TST_B_imm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001100--------";
    CONSTANT XTRCT_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1101"; -- XTRCT Rm,Rn
    CONSTANT XOR_Rm_Rn : STD_LOGIC_VECTOR(15 DOWNTO 0) := "0010--------1010";
    CONSTANT XOR_imm_R0 : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001010--------";
    CONSTANT XOR_B_imm_GBR : STD_LOGIC_VECTOR(15 DOWNTO 0) := "11001110--------";
END SH2_IR_Constants;

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.SH2_CPU_Constants.ALL;
USE work.SH2_IR_Constants.ALL;
USE work.array_type_pkg.ALL;
USE ieee.std_logic_textio.ALL; -- Needed for to_hstring
ENTITY CPUtoplevel IS
    PORT (

        Reset : IN STD_LOGIC; -- reset signal (active low)

        NMI : IN STD_LOGIC; -- non-maskable interrupt signal (falling edge)
        INT : IN STD_LOGIC; -- maskable interrupt signal (active low)

        RE0 : OUT STD_LOGIC; -- first byte active low read enable
        RE1 : OUT STD_LOGIC; -- second byte active low read enable
        RE2 : OUT STD_LOGIC; -- third byte active low read enable
        RE3 : OUT STD_LOGIC; -- fourth byte active low read enable
        WE0 : OUT STD_LOGIC; -- first byte active low write enable
        WE1 : OUT STD_LOGIC; -- second byte active low write enable
        WE2 : OUT STD_LOGIC; -- third byte active low write enable
        WE3 : OUT STD_LOGIC; -- fourth byte active low write enable

        SH2clock : IN STD_LOGIC;
        SH2DataBus : BUFFER STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0); -- stores data to read/write from memory
        SH2AddressBus : BUFFER STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) -- stores address to read/write from memory

    );
END CPUtoplevel;
ARCHITECTURE Structural OF CPUtoplevel IS

    -- Control Signals --
    --==================================================================================================================================================
    ------------------------------------------------------------------------------------------------------------------
    -- REG ARRAY FROM CONTROL UNIT INPUTS (for selecting reg in/out control)
    SIGNAL SH2RegIn : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SH2RegInSel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2RegStore : STD_LOGIC := '0';
    SIGNAL SH2RegASel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2RegBSel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2RegAx : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SH2RegAxIn : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SH2RegAxInSel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2RegAxStore : STD_LOGIC := '0';
    SIGNAL SH2RegA1Sel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2RegA2Sel : INTEGER RANGE regCount - 1 DOWNTO 0 := 0;
    ------------------------------------------------------------------------------------------------------------------
    -- ALU FROM CONTROL UNIT INPUTS (for ALU operation control)
    SIGNAL SH2FCmd : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '0'); -- F-Block operation
    SIGNAL SH2Cin : STD_LOGIC := '0'; -- Loads in the carry in bit
    SIGNAL SH2CinCmd : STD_LOGIC_VECTOR(1 DOWNTO 0) := (OTHERS => '0'); -- carry in operation
    SIGNAL SH2SCmd : STD_LOGIC_VECTOR(2 DOWNTO 0) := (OTHERS => '0'); -- shift operation
    SIGNAL SH2ALUCmd : STD_LOGIC_VECTOR(1 DOWNTO 0) := (OTHERS => '0'); -- ALU result select
    -- ALU additional from control line inputs (not directly from generic ALU)
    SIGNAL SH2ALUImmediateOperand : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- control unit should pad it (with 1s or 0s
    -- based on whether it's signed or not)
    -- before giving us immediate operand
    SIGNAL SH2ALUUseImmediateOperand : STD_LOGIC; -- 1 for use immediate operand, 0 otherwise
    SIGNAL SH2ALUOpAImmediate : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- control unit should pad it (with 1s or 0s
    -- based on whether it's signed or not)
    -- before giving us immediate operand
    SIGNAL SH2ALUOpAUseImmediateOperand : STD_LOGIC; -- 1 for use immediate operand, 0 otherwise
    -- ALU OUTPUTS
    SIGNAL SH2ALUResult : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- ALU result
    SIGNAL FlagBus : STD_LOGIC_VECTOR(4 DOWNTO 0) := (OTHERS => '0'); -- Flags are Cout, HalfCout, Overflow, Zero, Sign
    ------------------------------------------------------------------------------------------------------------------
    -- DMAU FROM CONTROL LINE INPUTS
    SIGNAL SH2DMAUReset : STD_LOGIC := '0';
    SIGNAL SH2DMAUSrcSel : INTEGER RANGE dmauSourceCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2DMAUOffsetSel : INTEGER RANGE dmauOffsetCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2DMAUIncDecSel : STD_LOGIC := '0';
    SIGNAL SH2DMAUIncDecBit : INTEGER RANGE maxIncDecBitDMAU DOWNTO 0 := 0;
    SIGNAL SH2DMAUPrePostSel : STD_LOGIC := '0';
    -- DMAU added inputs (not directly from generic MAU)
    SIGNAL DMAUImmediateSource : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL DMAUImmediateOffset : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    -- DMAU OUTPUTS
    SIGNAL SH2CalculatedDataAddress : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- DMAU output address
    SIGNAL HoldCalculatedDataAddress : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- save DMAU output address
    -- for write on next clock
    SIGNAL DMAUPostIncDecSrc : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- DMAU input address, updated with inc/dec
    SIGNAL DMAUAddressIndex : INTEGER RANGE 3 DOWNTO 0 := 0; -- if the DMAU output address is x0403, this would be 3, for example

    -- Read and Write flags that the PMAU sets
    SIGNAL WriteToMemoryB : STD_LOGIC := NO_WRITE_TO_MEMORY; -- active high
    SIGNAL WriteToMemoryW : STD_LOGIC := NO_WRITE_TO_MEMORY;
    SIGNAL WriteToMemoryL : STD_LOGIC := NO_WRITE_TO_MEMORY;
    SIGNAL ReadFromMemoryB : STD_LOGIC := NO_WRITE_TO_MEMORY; -- active high
    SIGNAL ReadFromMemoryW : STD_LOGIC := NO_WRITE_TO_MEMORY;
    SIGNAL ReadFromMemoryL : STD_LOGIC := NO_WRITE_TO_MEMORY;

    -------------------------------------------------------------------------------------
    -- PMAU FROM CONTROL LINE INPUTS
    SIGNAL SH2PMAUHold : STD_LOGIC := '0';
    SIGNAL SH2PMAUSrcSel : INTEGER RANGE pmauSourceCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2PMAUOffsetSel : INTEGER RANGE pmauOffsetCount - 1 DOWNTO 0 := 0;
    SIGNAL SH2PMAUIncDecSel : STD_LOGIC := '0';
    SIGNAL SH2PMAUIncDecBit : INTEGER RANGE maxIncDecBitPMAU DOWNTO 0 := 0;
    SIGNAL SH2PMAUPrePostSel : STD_LOGIC := '0';
    -- PMAU added inputs (not directly from generic MAU)
    SIGNAL PMAUImmediateSource : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL PMAUImmediateOffset : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');

    -- PMAU OUTPUTS
    SIGNAL SH2ProgramAddressBus : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- PMAU input address, updated
    -- (Control unit uses to update PC)
    ------------------------------------------------------------------------------------------

    -- Outputs
    --==================================================================================================================================================
    -- CONTROL OUTPUTS
    SIGNAL SH2SelDataBus : INTEGER RANGE NUM_DATA_BUS_OPTIONS DOWNTO 0 := OPEN_DATA_BUS; -- do not update, update with reg output, or update with ALU output
    SIGNAL SH2SelAddressBus : INTEGER RANGE NUM_ADDRESS_BUS_OPTIONS DOWNTO 0 := OPEN_ADDRESS_BUS; -- do not update, update with PMAU address out, or update with DMAU address out
    ------------------------------------------------------------------------------------------
    -- Outputs of registers; get hooked up to ALU and PMAU and DMAU
    SIGNAL RegArrayOutA : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL RegArrayOutB : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL RegArrayOutA1 : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL RegArrayOutA2 : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL HoldRegA : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL HoldRegA2 : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL SH2PC : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- the PC: a very special register!
    SIGNAL SH2PC_next : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- what to set PC to on next rising edge of clock
    SIGNAL SH2PC_postincdec : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0'); -- PC post incremented/decremented
    ------------------------------------------------------------------------------------------

    -- Signals and states
    --==================================================================================================================================================
    -- CPU top level signals; finite state machine and IR
    TYPE states IS (ZERO_CLK, FETCH_IR, END_OF_FILE);
    --TWO_CLK_W, TWO_CLK_R, THREE_CLK_R, THREE_CLK_W);
    SIGNAL CurrentState : states;

    SIGNAL InstructionReg : STD_LOGIC_VECTOR(instrLen - 1 DOWNTO 0) := (OTHERS => 'Z'); -- IR
    SIGNAL LatchedIR : STD_LOGIC_VECTOR(instrLen - 1 DOWNTO 0) := (OTHERS => 'Z'); -- IR
    SIGNAL ClockCounter : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0); -- what clock cycle are we on?

    -- Multi-clock and pipline signals
    SIGNAL MultiClockReg : STD_LOGIC_VECTOR(instrLen - 1 DOWNTO 0); --Holds the multiclock instruction that is executed
    SIGNAL ClockTwo : STD_LOGIC := '0'; --Clock cycle for multiclock instructions
    SIGNAL ClockThree : STD_LOGIC := '0'; --Clock cycle for multiclock instructions
    SIGNAL LatchedClockTwo : STD_LOGIC := '0';
    SIGNAL LatchedClockThree : STD_LOGIC := '0';
    SIGNAL DummyPc : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0); --Holds the new PC value to load
    SIGNAL StorePc : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0); --Holds the old PC value to push to PR
    SIGNAL OffsetPc : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0); --Holds the offset PC value to load

    CONSTANT PIPELINE_HALT : STD_LOGIC := '1';
    CONSTANT NO_PIPELINE_HALT : STD_LOGIC := '0';
    SIGNAL PipelineHalt : STD_LOGIC := NO_PIPELINE_HALT; -- active high: 1 to halt, 0 to not halt
    SIGNAL LatchedPipelineHalt : STD_LOGIC := NO_PIPELINE_HALT; -- clock-latched version of PipelineHalt
BEGIN

    -- ================================================================================================== Entity Instantiations
    -- Instantiate register array
    SH2RegArray : ENTITY work.SH2RegArray
        PORT MAP(
            SH2RegIn => SH2RegIn, -- hook up to port inputs
            SH2RegInSel => SH2RegInSel, -- so control unit can input
            SH2RegStore => SH2RegStore,
            SH2RegASel => SH2RegASel,
            SH2RegBSel => SH2RegBSel,
            SH2RegAxIn => SH2RegAxIn,
            Sh2RegAxInSel => SH2RegAxInSel,
            SH2RegAxStore => SH2RegAxStore,
            SH2RegA1Sel => SH2RegA1Sel,
            SH2RegA2Sel => SH2RegA2Sel,
            SH2clock => SH2clock,
            SH2RegA => RegArrayOutA,
            SH2RegB => RegArrayOutB,
            SH2RegA1 => RegArrayOutA1,
            SH2RegA2 => RegArrayOutA2
        );
    -- Instantiate ALU
    SH2ALU : ENTITY work.SH2ALU
        PORT MAP(
            SH2ALUOpA => RegArrayOutA, -- Control unit will set operands,
            SH2ALUOpB => RegArrayOutA2, -- to be output from the register array (if they so exist)
            SH2ALUImmediateOperand => SH2ALUImmediateOperand, -- can also be immediate (in instruction)
            SH2ALUOpAImmediate => SH2ALUOpAImmediate,
            SH2ALUOpAUseImmediateOperand => SH2ALUOPAUseImmediateOperand,
            SH2ALUUseImmediateOperand => SH2ALUUseImmediateOperand,
            SH2Cin => SH2Cin, -- Cin comes from T bit of SR, which is the rightmost bit                    
            SH2FCmd => SH2FCmd,
            SH2CinCmd => SH2CinCmd,
            SH2SCmd => SH2SCmd,
            SH2ALUCmd => SH2ALUCmd,
            SH2ALUResult => SH2ALUResult, -- now we are just hooking up outputs
            FlagBus => FlagBus
        );

    -- Instantiate DMAU
    SH2DMAU : ENTITY work.SH2DMAU
        PORT MAP(
            SH2DMAUGBRSource => RegArrayOutA1,
            SH2DMAURegSource => RegArrayOutA,
            SH2DMAUImmediateSource => DMAUImmediateSource,
            SH2DMAURegOffset => RegArrayOutB,
            SH2DMAUImmediateOffset => DMAUImmediateOffset,
            SH2DMAUSrcSel => SH2DMAUSrcSel,
            SH2DMAUOffsetSel => SH2DMAUOffsetSel,
            SH2DMAUIncDecSel => SH2DMAUIncDecSel,
            SH2DMAUIncDecBit => SH2DMAUIncDecBit,
            SH2DMAUPrePostSel => SH2DMAUPrePostSel,
            SH2DataAddressBus => SH2CalculatedDataAddress,
            SH2DataAddressSrc => DMAUPostIncDecSrc
        );

    -- Instantiate PMAU
    SH2PMAU : ENTITY work.SH2PMAU
        PORT MAP(
            SH2PR => RegArrayOutA1, -- make PR come out on the A1 output reg
            SH2PC => SH2PC,
            SH2PMAURegSource => RegArrayOutA,
            SH2PMAUImmediateSource => PMAUImmediateSource,
            SH2PMAURegOffset => RegArrayOutB,
            SH2PMAUImmediateOffset => PMAUImmediateOffset,
            SH2PMAUSrcSel => SH2PMAUSrcSel,
            SH2PMAUOffsetSel => SH2PMAUOffsetSel,
            SH2PMAUIncDecSel => SH2PMAUIncDecSel,
            SH2PMAUIncDecBit => SH2PMAUIncDecBit,
            SH2PMAUPrePostSel => SH2PMAUPrePostSel,
            SH2ProgramAddressBus => SH2PC_next, --make the PC come out into here
            SH2PostIncDecAddressBus => SH2PC_postincdec
        );

    -- ================================================================================================== Finite State Machine
    updatePCandIRandSetNextState : PROCESS (SH2clock)
        --========================================================== Procedures
        PROCEDURE setPCZero IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_IMM;
            SH2PMAUOffsetSel <= DEFAULT_OFFSET_SEL;
            SH2PMAUIncDecSel <= DEFAULT_DEC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= DEFAULT_POST_SEL;
            PMAUImmediateSource <= DMAU_ZERO_IMM;
            PMAUImmediateOffset <= MAU_ZERO_OFFSET;
        END PROCEDURE;

        PROCEDURE holdPC IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_PC;
            SH2PMAUOffsetSel <= PMAU_OFFSET_SEL_ZEROES;
            SH2PMAUIncDecSel <= DEFAULT_INC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= MAU_POST_SEL;
            PMAUImmediateSource <= DMAU_ZERO_IMM;
            PMAUImmediateOffset <= MAU_ZERO_OFFSET;
            SH2PC <= SH2PC_next;
        END PROCEDURE;

        PROCEDURE incPC IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_PC;
            SH2PMAUOffsetSel <= PMAU_OFFSET_SEL_ZEROES;
            SH2PMAUIncDecSel <= DEFAULT_INC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= MAU_PRE_SEL;
            PMAUImmediateSource <= DMAU_ZERO_IMM;
            PMAUImmediateOffset <= MAU_ZERO_OFFSET;
            SH2PC <= SH2PC_next;
        END PROCEDURE;

        PROCEDURE disableReadWrite IS
        BEGIN
            WE0 <= '1';
            WE1 <= '1';
            WE2 <= '1';
            WE3 <= '1';
            RE0 <= '1';
            RE1 <= '1';
            RE2 <= '1';
            RE3 <= '1';
        END PROCEDURE;

        PROCEDURE PCLoadImmediate IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_IMM;
            SH2PMAUOffsetSel <= DEFAULT_OFFSET_SEL;
            SH2PMAUIncDecSel <= DEFAULT_DEC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= DEFAULT_POST_SEL;
            PMAUImmediateSource <= DummyPc;
            PMAUImmediateOffset <= MAU_ZERO_OFFSET;
            SH2PC <= SH2PC_next;

        END PROCEDURE;

        PROCEDURE PCLoadTwoXOffset IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_PC;
            SH2PMAUOffsetSel <= PMAU_OFFSET_SEL_REG_OFFSET_x2;
            SH2PMAUIncDecSel <= DEFAULT_DEC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= DEFAULT_POST_SEL;
            PMAUImmediateSource <= DMAU_ZERO_IMM;
            PMAUImmediateOffset <= OffsetPc;
            SH2PC <= SH2PC_next;
        END PROCEDURE;

        PROCEDURE PCLoadRegisterOffset IS
        BEGIN
            SH2PMAUSrcSel <= PMAU_SRC_SEL_PC;
            SH2PMAUOffsetSel <= PMAU_OFFSET_SEL_REG_OFFSET_x1;
            SH2PMAUIncDecSel <= DEFAULT_DEC_SEL;
            SH2PMAUIncDecBit <= DEFAULT_BIT;
            SH2PMAUPrePostSel <= DEFAULT_POST_SEL;
            PMAUImmediateSource <= DMAU_ZERO_IMM;
            PMAUImmediateOffset <= OffsetPc;
            SH2PC <= SH2PC_next;
        END PROCEDURE;

    BEGIN

        -- Rising edge: Update state, load PC, load IR
        --=====================================================================================
        IF rising_edge(SH2clock) THEN

            disableReadWrite;

            -- Update state on rising edge
            CASE CurrentState IS
                WHEN ZERO_CLK =>

                    setPCZero;
                    ------------------------------------------------ Update state
                    IF (Reset = '1') THEN
                        CurrentState <= FETCH_IR; -- CPU is enabled for the first time
                        -- For the next state: prepare to load in the first instruction. Data bus needs to be high-Z.
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT;
                        SH2SelDataBus <= HOLD_DATA_BUS;
                    ELSE
                        CurrentState <= ZERO_CLK; -- CPU is still in reset mode (off)
                        -- For the next state: Set data, address buses to high impedance so that test bench can write them
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                    END IF;
                WHEN FETCH_IR =>

                    -------------------------------------------------- Update the IR, clock cycle, and PC

                    RE0 <= '0';
                    RE1 <= '0';
                    RE2 <= '1';
                    RE3 <= '1'; -- Read low bytes in (instructions stored in low bytes)
                    ClockCounter <= ONE_CLOCK; --Set clock counter back to 1
                    IF (PipelineHalt = NO_PIPELINE_HALT) THEN
                        incPC;
                    ELSE
                        holdPC;
                    END IF;

                    ------------------------------------------------ Set next state
                    IF (InstructionReg = "XXXXXXXXXXXXXXXX") THEN
                        REPORT "End of file reached.";
                        CurrentState <= END_OF_FILE;

                        -- For the next state: Set data, address buses to high impedance so that test bench can write them
                        SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                        SH2SelDataBus <= HOLD_DATA_BUS;

                    ELSE
                        CurrentState <= FETCH_IR;

                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_PMAU_OUT; -- Open data bus for next read-in of codespace
                        SH2SelDataBus <= OPEN_DATA_BUS;

                    END IF;

                    IF (ClockTwo = '1') THEN
                        IF std_match(JMP_Rm, MultiClockReg) THEN
                            PCLoadImmediate; --Load the Rm address to jump to
                        ELSIF std_match(JSR_Rm, MultiClockReg) THEN
                            PCLoadImmediate; --Load the Rm address to jump to 
                        ELSIF std_match(RTS, MultiClockReg) THEN
                            PCLoadImmediate; --Load the PR address to jump back to
                        ELSIF std_match(BT_disp, MultiClockReg) THEN
                            PCLoadImmediate; --IDK
                        ELSIF std_match(BT_S_disp, MultiClockReg) THEN
                            PCLoadTwoXOffset; --Load the 2x displacement into offset to jump to; 
                        ELSIF std_match(BF_disp, MultiClockReg) THEN
                            PCLoadImmediate; --IDK
                        ELSIF std_match(BF_S_disp, MultiClockReg) THEN
                            PCLoadTwoXOffset; --Load the 2x displacement into offset to jump to
                        ELSIF std_match(BRA_disp, MultiClockReg) THEN
                            PCLoadTwoXOffset; --Load the 2x displacement into offset to jump to
                        ELSIF std_match(BRAF_Rm, MultiClockReg) THEN
                            PCLoadRegisterOffset;--Load the register displacement into offset to jump to
                        ELSIF std_match(BSR_disp, MultiClockReg) THEN
                            PCLoadRegisterOffset;--Load the register displacement into offset to jump to
                        ELSIF std_match(BSRF_Rm, MultiClockReg) THEN
                            PCLoadImmediate; --IDK
                        ELSE
                        END IF;

                    ELSE

                    END IF;

                WHEN OTHERS => -- End of File or invalid state

                    holdPC;
                    CurrentState <= END_OF_FILE;
                    InstructionReg <= NOP;

                    -- For the next state: prepare to load in the first instruction. Data bus needs to be high-Z
                    SH2SelAddressBus <= OPEN_ADDRESS_BUS;
                    SH2SelDataBus <= OPEN_DATA_BUS;

            END CASE;

            IF (Reset = '0') THEN
                CurrentState <= ZERO_CLK; -- We are resetting
            END IF;

        END IF;

        -- Falling edge: Update select address and data bus signals (after they were set by InstrMatch on rising edge)
        --=====================================================================================
        IF falling_edge(SH2clock) THEN

            disableReadWrite;

            -- Update select address and data bus signals
            CASE CurrentState IS
                WHEN ZERO_CLK =>
                    -- nothing to do

                WHEN FETCH_IR =>

                    -- Figure out which bits to write to RAM
                    -- assume address, data bus correctly set in instruction matching
                    IF (WriteToMemoryB = WRITE_TO_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT;

                        CASE DMAUAddressIndex IS
                            WHEN 0 =>
                                WE3 <= '0';
                                WE2 <= '1';
                                WE1 <= '1';
                                WE0 <= '1';
                            WHEN 1 =>
                                WE3 <= '1';
                                WE2 <= '0';
                                WE1 <= '1';
                                WE0 <= '1';
                            WHEN 2 =>
                                WE3 <= '1';
                                WE2 <= '1';
                                WE1 <= '0';
                                WE0 <= '1';
                            WHEN 3 =>
                                WE3 <= '1';
                                WE2 <= '1';
                                WE1 <= '1';
                                WE0 <= '0';
                            WHEN OTHERS =>
                                WE3 <= '1';
                                WE2 <= '1';
                                WE1 <= '1';
                                WE0 <= '1';
                        END CASE;

                    ELSIF (WriteToMemoryW = WRITE_TO_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT;

                        CASE DMAUAddressIndex IS
                            WHEN 0 =>
                                WE3 <= '0';
                                WE2 <= '0';
                                WE1 <= '1';
                                WE0 <= '1';
                            WHEN 1 =>
                                WE3 <= '1';
                                WE2 <= '0';
                                WE1 <= '0';
                                WE0 <= '1';
                            WHEN 2 =>
                                WE3 <= '1';
                                WE2 <= '1';
                                WE1 <= '0';
                                WE0 <= '0';
                            WHEN OTHERS =>
                                WE3 <= '1';
                                WE2 <= '1';
                                WE1 <= '1';
                                WE0 <= '1';
                        END CASE;
                    ELSIF (WriteToMemoryL = WRITE_TO_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= SET_DATA_BUS_TO_REG_A2_OUT;
                        WE0 <= '0';
                        WE1 <= '0';
                        WE2 <= '0';
                        WE3 <= '0'; -- write the whole longword

                    END IF;

                    -- Figure out which bits to load from RAM
                    -- assume address, data bus correctly set in instruction matching
                    IF (ReadFromMemoryB = READ_FROM_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;

                        CASE DMAUAddressIndex IS
                            WHEN 0 =>
                                RE3 <= '0';
                                RE2 <= '1';
                                RE1 <= '1';
                                RE0 <= '1';
                            WHEN 1 =>
                                RE3 <= '1';
                                RE2 <= '0';
                                RE1 <= '1';
                                RE0 <= '1';
                            WHEN 2 =>
                                RE3 <= '1';
                                RE2 <= '1';
                                RE1 <= '0';
                                RE0 <= '1';
                            WHEN 3 =>
                                RE3 <= '1';
                                RE2 <= '1';
                                RE1 <= '1';
                                RE0 <= '0';
                            WHEN OTHERS =>
                                RE3 <= '1';
                                RE2 <= '1';
                                RE1 <= '1';
                                RE0 <= '1';
                        END CASE;

                    ELSIF (ReadFromMemoryW = READ_FROM_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;

                        CASE DMAUAddressIndex IS
                            WHEN 0 =>
                                RE3 <= '0';
                                RE2 <= '0';
                                RE1 <= '1';
                                RE0 <= '1';
                            WHEN 1 =>
                                RE3 <= '1';
                                RE2 <= '0';
                                RE1 <= '0';
                                RE0 <= '1';
                            WHEN 2 =>
                                RE3 <= '1';
                                RE2 <= '1';
                                RE1 <= '0';
                                RE0 <= '0';
                            WHEN OTHERS =>
                                RE3 <= '1';
                                RE2 <= '1';
                                RE1 <= '1';
                                RE0 <= '1';
                        END CASE;

                    ELSIF (ReadFromMemoryL = READ_FROM_MEMORY) THEN
                        SH2SelAddressBus <= SET_ADDRESS_BUS_TO_DMAU_OUT;
                        SH2SelDataBus <= OPEN_DATA_BUS;
                        RE0 <= '0';
                        RE1 <= '0';
                        RE2 <= '0';
                        RE3 <= '0'; -- assume address, data bus correctly set in instruction matching
                    END IF;

                WHEN OTHERS => -- halt the CPU
                    InstructionReg <= NOP;

            END CASE;
        END IF;
    END PROCESS updatePCandIRandSetNextState;

    --Update the CurrentState to the NextState every rising edge of the clock
    --Set Read and Write to inactive during the rising edge of the clock
    -- ================================================================================================== Instruction Decoding, State Determination
    --combinational if statements
    --Matches the 
    --at the end of the matches -> update the currentstate with nextState variable
    matchInstruction : PROCESS (InstructionReg)

        -- Set default instruction-specific control signals
        -- Does not include PMAU and address/data bus setting logic, because that is determined
        -- by the state machine

        --Temproary variable to help with the subtractions with carrys
        VARIABLE SubCarryBus : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');

        PROCEDURE SetDefaultControlSignals IS
        BEGIN
            -- Default RegArray inputs: Do not input any registers, 
            -- only put Reg0 on output buses 

            -- Default ALU inputs. Immediate is 0 and not used by default. Carry ins are also 0
            SH2Cin <= DEFAULT_ALU_CIN;
            SH2FCmd <= DEFAULT_ALU_F_CMD;
            SH2CinCmd <= DEFAULT_ALU_CIN_CMD;
            SH2SCmd <= DEFAULT_ALU_S_CMD;
            SH2ALUCmd <= DEFAUL_ALU_CMD;
            SH2ALUImmediateOperand <= DEFAULT_ALU_IMM_OP;
            SH2ALUUseImmediateOperand <= DEFAULT_ALU_USE_IMM;
            SH2ALUOpAUseImmediateOperand <= DEFAULT_ALU_USE_IMM;
            SH2ALUOpAImmediate <= DEFAULT_ALU_IMM_OP;

            -- Default DMAU inputs
            SH2DMAUSrcSel <= DMAU_SRC_SEL_IMM;
            SH2DMAUOffsetSel <= DEFAULT_OFFSET_SEL;
            SH2DMAUIncDecSel <= DEFAULT_DEC_SEL;
            SH2DMAUIncDecBit <= DEFAULT_BIT;
            SH2DMAUPrePostSel <= DEFAULT_POST_SEL;
            DMAUImmediateSource <= DMAU_ZERO_IMM;
            DMAUImmediateOffset <= MAU_ZERO_OFFSET;

            -- Reset reads and writes;
            WriteToMemoryB <= NO_WRITE_TO_MEMORY;
            WriteToMemoryW <= NO_WRITE_TO_MEMORY;
            WriteToMemoryL <= NO_WRITE_TO_MEMORY;
            ReadFromMemoryB <= NO_READ_FROM_MEMORY;
            ReadFromMemoryW <= NO_READ_FROM_MEMORY;
            ReadFromMemoryL <= NO_READ_FROM_MEMORY;

        END PROCEDURE;

    BEGIN

        IF CurrentState = FETCH_IR THEN
            --Default all the units
            SetDefaultControlSignals;

            --  ==================================================================================================
            -- ARITHMETIC
            -- ==================================================================================================
            IF std_match(InstructionReg, ADD_imm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 

                --Setting ALU control signals
                SH2FCmd <= "1010"; --Use OpB for the Adder
                SH2ALUCmd <= "01"; --Select the Adder Output
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0); --Select the immediate value from the IR
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value

            ELSIF std_match(InstructionReg, ADD_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "1010"; --Use OpB for the Adder
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, ADDC_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2RegA1Sel <= REG_SR; --Grab the status register to get the T bit
                SH2Cin <= RegArrayOutA1(0); --Load in the T-bit as Cin
                SH2CinCmd <= "10"; --Set the Cin Adder command to take in Cin
                SH2FCmd <= "1010"; --Use OpB for the Adder
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, ADDV_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel <= REG_SR; --Grab the status register to get the T bit

                --Setting ALU control signals
                SH2FCmd <= "1010"; --Use OpB for the Adder
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, SUB_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, SUBC_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel <= REG_SR; --Grab the status register to get the T bit

                --Setting ALU control signals
                --To do: Rn - Rm - T => Rn - (Rm + T)
                SubCarryBus := STD_LOGIC_VECTOR(to_unsigned(
                    to_integer(unsigned(RegArrayOutA2)) +
                    to_integer(unsigned(STD_LOGIC_VECTOR'("0" & RegArrayOutA1(0)))),
                    RegArrayOutA2'length));

                SH2ALUImmediateOperand <= SubCarryBus;
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value for OpB

                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, SUBV_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel <= REG_SR; --Grab the status register to get the T bit

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, NEG_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2ALUOpAImmediate <= DEFAULT_ALU_IMM_OP;
                SH2ALUOpAUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output    

            ELSIF std_match(InstructionReg, NEGC_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2ALUOpAImmediate <= DEFAULT_ALU_IMM_OP;
                SH2ALUOpAUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm
                SH2RegA1Sel <= REG_SR; --Grab the status register to get the T bit

                --Setting ALU control signals
                --To do: 0 - Rm - T => 0 - (Rm + T)
                SubCarryBus := STD_LOGIC_VECTOR(to_unsigned(
                    to_integer(unsigned(RegArrayOutA2)) +
                    to_integer(unsigned(STD_LOGIC_VECTOR'("0" & RegArrayOutA1(0)))),
                    RegArrayOutA2'length));

                SH2ALUImmediateOperand <= SubCarryBus;
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value for OpB

                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, EXTU_B_Rm_Rn) THEN
                SH2ALUOpAImmediate <= BYTE_MASK;
                SH2ALUOpAUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(InstructionReg, EXTU_W_Rm_Rn) THEN
                SH2ALUOpAImmediate <= WORD_MASK;
                SH2ALUOpAUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(InstructionReg, EXTS_B_Rm_Rn) THEN

                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpA of ALU comes out of RegArray at Rn 

                SH2FCmd <= "1100"; --Select OpA
                SH2ALUCmd <= ALU_FB_SEL; --Select the Fblock Output

            ELSIF std_match(InstructionReg, EXTS_W_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpA of ALU comes out of RegArray at Rn 

                SH2FCmd <= "1100"; --Select OpA
                SH2ALUCmd <= ALU_FB_SEL; --Select the Fblock Output

            ELSIF std_match(InstructionReg, DT_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2ALUImmediateOperand <= "00000000000000000000000000000001";
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output

            ELSIF std_match(InstructionReg, CMP_EQ_imm_R0) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0); --Select the immediate value from the IR
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value

            ELSIF std_match(InstructionReg, CMP_EQ_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
            ELSIF std_match(InstructionReg, CMP_HS_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
            ELSIF std_match(InstructionReg, CMP_GE_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
            ELSIF std_match(InstructionReg, CMP_HI_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
            ELSIF std_match(InstructionReg, CMP_GT_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                SH2ALUCmd <= "01"; --Select the Adder Output
            ELSIF std_match(InstructionReg, CMP_PL_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2ALUImmediateOperand <= ALU_ZERO_IMM;
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
            ELSIF std_match(InstructionReg, CMP_PZ_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2ALUImmediateOperand <= ALU_ZERO_IMM;
                SH2ALUUseImmediateOperand <= ALU_USE_IMM; --Use the immediate value
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
            ELSIF std_match(InstructionReg, CMP_STR_Rm_Rn) THEN
                -- Setting register ops for ALU
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn 
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); --OpB of ALU comes out of RegArray at Rm

                --Setting ALU control signals
                SH2FCmd <= "0101"; --Use not OpB for the Adder
                SH2CinCmd <= "01"; --Use the 1 option into the Adder
                --(makes one's complement -> two's complement to do subtraction)
                --  ==================================================================================================
                -- SHIFTS (0/8) : Needs testing
                --  ==================================================================================================
            ELSIF std_match(SHLL_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn  
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting

                --Setting ALU control signals
                SH2SCmd <= "000"; --Left shift left
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(SHLR_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn   
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting                                 

                --Setting ALU control signals
                SH2SCmd <= "100"; --LSR
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(SHAR_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn    
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting

                --Setting ALU control signals
                SH2SCmd <= "101"; --ASR
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(SHAL_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn  
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting                    

                --Setting ALU control signals
                SH2SCmd <= "000"; --LSL
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(ROTCR_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals                         
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting

                --Setting ALU control signals
                SH2Cin <= RegArrayOutA2(0); --Feed in T-bit into RRC
                SH2SCmd <= "111"; --RRC
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(ROTCL_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals                                
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting

                --Setting ALU control signals
                SH2Cin <= RegArrayOutA2(0); --Feed in T-bit into RLC
                SH2SCmd <= "011"; --Left shift left
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(ROTR_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn                                                
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting

                --Setting ALU control signals
                SH2SCmd <= "110"; --ROR
                SH2ALUCmd <= "10"; --Select the shifter output

            ELSIF std_match(ROTL_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --OpA of ALU comes out of RegArray at Rn     
                SH2RegA2Sel <= REG_SR; --Grab the status register for Shifting                             

                --Setting ALU control signals
                SH2SCmd <= "010"; --ROL
                SH2ALUCmd <= "10"; --Select the shifter output

                --  ==================================================================================================
                -- LOGICAL 0/9 Needs testing
                --  ==================================================================================================
            ELSIF std_match(AND_Rm_Rn, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4)));
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(AND_imm_R0, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0);
                SH2ALUUseImmediateOperand <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(TST_Rm_Rn, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4)));
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(TST_imm_R0, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0);
                SH2ALUUseImmediateOperand <= ALU_USE_IMM;
                SH2RegA1Sel <= REG_SR;

                --Setting ALU control signals
                SH2FCmd <= "1000";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(OR_Rm_Rn, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4)));
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));

                --Setting ALU control signals
                SH2FCmd <= "1110";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(OR_imm_R0, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0);
                SH2ALUUseImmediateOperand <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd <= "1110";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(XOR_Rm_Rn, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4)));
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));

                --Setting ALU control signals
                SH2FCmd <= "0110";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(XOR_imm_R0, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= REG_ZEROTH_SEL;
                SH2ALUImmediateOperand <= (23 DOWNTO 0 => '0') & InstructionReg(7 DOWNTO 0);
                SH2ALUUseImmediateOperand <= ALU_USE_IMM;

                --Setting ALU control signals
                SH2FCmd <= "0110";
                SH2ALUCmd <= ALU_FB_SEL;

            ELSIF std_match(NOT_Rm_Rn, InstructionReg) THEN
                --Setting Reg Array control signals
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));

                --Setting ALU control signals
                SH2FCmd <= "0011";
                SH2ALUCmd <= ALU_FB_SEL;

                --  ==================================================================================================
                -- LOAD
                --  ==================================================================================================
                -- Load immediate
            ELSIF std_match(MOV_IMM_TO_Rn, InstructionReg) THEN
                -- Nothing to precalculate here. We'll do the loading in the execute stage.

                -- Load from reg address directly
            ELSIF std_match(MOVB_atRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVW_atRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                ReadFromMemoryW <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVL_atRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read

                -- Load from reg address + reg address in R0
            ELSIF std_match(MOVB_atR0Rm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVW_atR0Rm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                ReadFromMemoryW <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVL_atR0Rm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read

                -- Load from reg address post-incremented
            ELSIF std_match(MOVB_atPostIncRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU post-increment the address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_INC_SEL;
                SH2DMAUPrePostSel <= MAU_POST_SEL;

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVW_atPostIncRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU post-increment the address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_INC_SEL;
                SH2DMAUPrePostSel <= MAU_POST_SEL;

                ReadFromMemoryW <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVL_atPostIncRm_TO_Rn, InstructionReg) THEN
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU post-increment the address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_INC_SEL;
                SH2DMAUPrePostSel <= MAU_POST_SEL;

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read

                -- Load from disp * (1,2,4) + reg address (into R0 or Rn)
            ELSIF std_match(MOVB_atDispRm_TO_R0, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1;

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVW_atDispRm_TO_R0, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x2;

                ReadFromMemoryW <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOVL_atDispRm_TO_Rn, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rm (at index m)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x4;

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read

                -- Load from dis * (1,2,4) + GBR (into R0)

            ELSIF std_match(MOV_B_R0_GBR, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A1)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1;

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOV_W_R0_GBR, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A1)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x2;

                ReadFromMemoryW <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(MOV_L_R0_GBR, InstructionReg) THEN

                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A1)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x4;

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read

                --  ==================================================================================================
                -- STORE
                --  ==================================================================================================

                -- Store value in Rm to RAM address in Rn
            ELSIF std_match(MOVB_Rm_TO_atRn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                WriteToMemoryB <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVW_Rm_TO_atRn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                WriteToMemoryW <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVL_Rm_TO_atRn, InstructionReg) THEN

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU take address directly from register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write

                -- Store value in Rm to (RAM address in Rn + RAM address in R0)
            ELSIF std_match(MOVB_Rm_TO_atR0Rn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                WriteToMemoryB <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVW_Rm_TO_atR0Rn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                WriteToMemoryW <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVL_Rm_TO_atR0Rn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)
                SH2RegBSel <= 0; -- Access offset inside R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_REG_OFFSET_x1;

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write

                -- Store value in Rm to (pre decremented RAM address in Rn)
            ELSIF std_match(MOVB_Rm_TO_atPreDecRn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

                WriteToMemoryB <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVW_Rm_TO_atPreDecRn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

                WriteToMemoryW <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVL_Rm_TO_atPreDecRn, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write

                -- Store value in Rm to ((RAM address in Rn) + (1,2,4)*disp)
            ELSIF std_match(MOVB_R0_TO_atDispRn, InstructionReg) THEN

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= 0; -- Access value at register R0 (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1;

                WriteToMemoryB <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVW_R0_TO_atDispRn, InstructionReg) THEN

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= 0; -- Access value at register R0 (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x2;

                WriteToMemoryW <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOVL_Rm_TO_atDispRn, InstructionReg) THEN

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Access value at register Rm (at index m)
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x4;

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write

                -- Store value in R0 to ((RAM address in GBR) + (1,2,4)*GBR) 
            ELSIF std_match(MOV_B_GBR_R0, InstructionReg) THEN

                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= 0; -- Access value at register R0
                SH2RegASel <= REG_GBR; -- Access address inside GBR

                -- Have DMAU sum the immediate and GBR address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1;

                WriteToMemoryB <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOV_W_GBR_R0, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= 0; -- Access value at register R0
                SH2RegASel <= REG_GBR; -- Access address inside GBR

                -- Have DMAU sum the immediate and GBR address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x2;

                WriteToMemoryW <= WRITE_TO_MEMORY; -- prepare for write

            ELSIF std_match(MOV_L_GBR_R0, InstructionReg) THEN
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= 0; -- Access value at register R0
                SH2RegASel <= REG_GBR; -- Access address inside GBR

                -- Have DMAU sum the immediate and GBR address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                DMAUImmediateOffset <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x4;

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write

                --  ==================================================================================================
                -- SYSTEM CONTROL
                --  ==================================================================================================
            ELSIF std_match(NOP, InstructionReg) THEN

                SetDefaultControlSignals;

            ELSIF std_match(SETT, InstructionReg) THEN
                SH2RegASel <= REG_SR; --Summon the status register
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output
            ELSIF std_match(LDC_Rm_SR, InstructionReg) THEN
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 0))); --Summon the status register
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output
            ELSIF std_match(STC_SR_Rn, InstructionReg) THEN
                SH2RegASel <= REG_SR; --Summon the status register
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(JMP_Rm, InstructionReg) THEN
                ClockTwo <= '1'; --Set up for the second clock
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Load the immediate address from register
                DummyPc <= RegArrayOutA; --Store the register
                MultiClockReg <= InstructionReg;
            ELSIF std_match(STC_GBR_Rn, InstructionReg) THEN
                SH2RegASel <= REG_GBR;
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(STC_VBR_Rn, InstructionReg) THEN
                SH2RegASel <= REG_VBR;
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(STS_PR_Rn, InstructionReg) THEN
                SH2RegASel <= REG_PR;
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(LDC_Rm_GBR, InstructionReg) THEN
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(LDC_Rm_VBR, InstructionReg) THEN
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(LDS_Rm_PR, InstructionReg) THEN
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                --Setting ALU control signals
                SH2FCmd <= "1100"; --Use OpA
                SH2CinCmd <= ALU_FB_SEL; --Select the OpA output

            ELSIF std_match(JSR_Rm, InstructionReg) THEN
                ClockTwo <= '1';
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Load the immediate address from register
                DummyPc <= RegArrayOutA; --Store the register
                StorePC <= SH2PC;
                MultiClockReg <= InstructionReg;
                --=================================================================
                --WAITTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTt 
                --=================================================================  
            ELSIF std_match(BF_disp, InstructionReg) THEN
                SH2RegA1Sel <= REG_SR;
                IF RegArrayOutA1(0) = '0' THEN
                    ClockTwo <= '1';
                ELSE
                    SetDefaultControlSignals;
                END IF;

            ELSIF std_match(BF_S_disp, InstructionReg) THEN
                SH2RegA1Sel <= REG_SR;
                IF RegArrayOutA1(0) = '0' THEN
                    ClockTwo <= '1';
                    OffsetPc <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                    MultiClockReg <= InstructionReg;
                ELSE
                    SetDefaultControlSignals;
                END IF;

            ELSIF std_match(RTE, InstructionReg) THEN
                ClockTwo <= '1';
            ELSIF std_match(RTS, InstructionReg) THEN
                ClockTwo <= '1';
                SH2RegASel <= REG_PR; --Load the immediate address from register
                DummyPc <= RegArrayOutA; --Store the register
                MultiClockReg <= InstructionReg;
                --=================================================================
                --WAITTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTt
                --=================================================================
            ELSIF std_match(BT_disp, InstructionReg) THEN
                SH2RegA1Sel <= REG_SR;
                IF RegArrayOutA1(0) = '1' THEN
                    ClockTwo <= '1';
                ELSE
                    SetDefaultControlSignals;
                END IF;

                ClockTwo <= '1';
            ELSIF std_match(BT_S_disp, InstructionReg) THEN
                SH2RegA1Sel <= REG_SR;
                IF RegArrayOutA1(0) = '1' THEN
                    ClockTwo <= '1';
                    OffsetPc <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                    MultiClockReg <= InstructionReg;
                ELSE
                    SetDefaultControlSignals;
                END IF;

            ELSIF std_match(BRA_disp, InstructionReg) THEN
                ClockTwo <= '1';
                OffsetPc <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                MultiClockReg <= InstructionReg;

            ELSIF std_match(BRAF_Rm, InstructionReg) THEN
                ClockTwo <= '1'; --Multiclock instruction, prepare for the second clock execution
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Load the offset from register
                OffsetPc <= RegArrayOutA; --Store the offset to the PC
                MultiClockReg <= InstructionReg; --Record the multiclock instruction for future reference

            ELSIF std_match(BSR_disp, InstructionReg) THEN
                ClockTwo <= '1';
                OffsetPc <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(3 DOWNTO 0)), regLen)); -- sign-extended immediate
                StorePC <= SH2PC; --Store the PC to PR later
                MultiClockReg <= InstructionReg;

            ELSIF std_match(BSRF_Rm, InstructionReg) THEN
                ClockTwo <= '1'; --Multiclock instruction, prepare for the second clock execution
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Load the offset from register
                OffsetPc <= RegArrayOutA; --Store the offset to the PC
                StorePC <= SH2PC; --Store the PC to PR later
                MultiClockReg <= InstructionReg; --Record the multiclock instruction for future reference

                -- ==================================================================================================
                -- ARITHMETIC
                -- ==================================================================================================
            ELSIF std_match(AND_B_imm_GBR, InstructionReg) THEN
                ClockTwo <= '1';
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A)
                SH2RegA2Sel <= 0; --Load the displacement from register R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG; --Select the GBR register input
                DMAUImmediateOffset <= RegArrayOutA2; --displacement in register R0
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1; --add the displacement from R0

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(OR_B_imm_GBR, InstructionReg) THEN
                ClockTwo <= '1';
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A)
                SH2RegA2Sel <= 0; --Load the displacement from register R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG; --Select the GBR register input
                DMAUImmediateOffset <= RegArrayOutA2; --displacement in register R0
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1; --add the displacement from R0

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read
            ELSIF std_match(TST_B_imm_GBR, InstructionReg) THEN
                ClockTwo <= '1';
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A)
                SH2RegA2Sel <= 0; --Load the displacement from register R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG; --Select the GBR register input
                DMAUImmediateOffset <= RegArrayOutA2; --displacement in register R0
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1; --add the displacement from R0

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(XOR_B_imm_GBR, InstructionReg) THEN
                ClockTwo <= '1';
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= REG_GBR; -- Access GBR (expected to come out on Reg A)
                SH2RegA2Sel <= 0; --Load the displacement from register R0

                -- Have DMAU sum the addresses from the registers
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG; --Select the GBR register input
                DMAUImmediateOffset <= RegArrayOutA2; --displacement in register R0
                SH2DMAUOffsetSel <= DMAU_OFFSET_SEL_IMM_OFFSET_x1; --add the displacement from R0

                ReadFromMemoryB <= READ_FROM_MEMORY; -- prepare for read

            ELSIF std_match(TAS_B_Rn, InstructionReg) THEN
                ClockTwo <= '1';
                --===========================
                -- System Register Control
                --===========================
            ELSIF std_match(STC_L_SR_Rn, InstructionReg) THEN
                -- Prepare to halt the pipeline to prevent other instr from writing SR
                MultiClockReg <= InstructionReg;
                ClockTwo <= '1';
                PipelineHalt <= PIPELINE_HALT;

                -- Prepare to grab the SR value to write to memory
                -- Setting Reg Array control signals                                             
                SH2RegA2Sel <= REG_SR; -- Access value at SR
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rn (at index n)

                -- Have DMAU pre-decrement the address from the register
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_DEC_SEL;
                SH2DMAUPrePostSel <= MAU_PRE_SEL;
                SH2DMAUIncDecBit <= 2; -- predecrement by 4

                WriteToMemoryL <= WRITE_TO_MEMORY; -- prepare for write 

            ELSIF std_match(LDC_L_Rm_SR, InstructionReg) THEN
                -- Prepare to halt the pipeline to prevent other instr from writing SR
                MultiClockReg <= InstructionReg;
                ClockTwo <= '1';
                PipelineHalt <= PIPELINE_HALT;

                -- Prepare to read @Rm into SR
                -- Setting Reg Array control signals: RegA = Reg source, RegB = Reg offset source                                             
                SH2RegASel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Access address inside register Rm (at index m)

                -- Have DMAU post-increment the address
                SH2DMAUSrcSel <= DMAU_SRC_SEL_REG;
                SH2DMAUIncDecSel <= MAU_INC_SEL;
                SH2DMAUPrePostSel <= MAU_POST_SEL;
                SH2DMAUIncDecBit <= 2; -- post increment by 4

                ReadFromMemoryL <= READ_FROM_MEMORY; -- prepare for read
            ELSE
                SetDefaultControlSignals;

            END IF;

            -- Pipeline forces a NOP to delay execution/pre-calculation execution
            -- of the one-clock instruction
            -- Moved before "second clock reset" so we don't accidently overwrite any
            -- of the signals from there.
            IF (LatchedPipelineHalt = PIPELINE_HALT) THEN
                setDefaultControlSignals;
            END IF;

                -- ==================================================================================================
                -- Second Clock Cycle Reset
                -- ==================================================================================================
            IF (LatchedClockTwo = '1') THEN
                IF std_match(JMP_Rm, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(JSR_Rm, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BF_disp, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(RTE, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(RTS, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BT_disp, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(BT_S_disp, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BRA_disp, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BRAF_Rm, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BSR_disp, MultiClockReg) THEN
                    ClockTwo <= '0';
                ELSIF std_match(BSRF_Rm, MultiClockReg) THEN
                    ClockTwo <= '0';

                    -- ==================================================================================================
                    -- ARITHMETIC
                    -- ==================================================================================================
                ELSIF std_match(AND_B_imm_GBR, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(OR_B_imm_GBR, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(TST_B_imm_GBR, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(XOR_B_imm_GBR, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                ELSIF std_match(TAS_B_Rn, MultiClockReg) THEN
                    ClockTwo <= '0';
                    ClockThree <= '1'; --Set the third clock
                    -- =========================
                    -- System Register Control
                    -- =========================
                ELSIF std_match(STC_L_SR_Rn, MultiClockReg) THEN
                    -- this is the last clock cycle of this instruction
                    ClockTwo <= '0';
                    PipelineHalt <= NO_PIPELINE_HALT;

                ELSIF std_match(LDC_L_Rm_SR, MultiClockReg) THEN
                    -- Clock update stuff
                    ClockTwo <= '0';
                    ClockThree <= '1';
                ELSE
                END IF;
            END IF;

                -- ==================================================================================================
                -- Third Clock Cycle Reset
                -- ==================================================================================================
            IF (LatchedClockThree = '1') THEN
                -- ==================================================================================================
                -- ARITHMETIC
                -- ==================================================================================================
                IF std_match(AND_B_imm_GBR, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(OR_B_imm_GBR, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(TST_B_imm_GBR, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(XOR_B_imm_GBR, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(TAS_B_Rn, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(BT_disp, MultiClockReg) THEN
                    ClockThree <= '0';
                ELSIF std_match(BF_disp, MultiClockReg) THEN
                    ClockThree <= '0';

                ELSIF std_match(LDC_L_Rm_SR, MultiClockReg) THEN
                    -- last clock: unpause pipeline
                    ClockTwo <= '0';
                    ClockThree <= '0';
                    PipelineHalt <= NO_PIPELINE_HALT;
                ELSE
                END IF;
            END IF;

        END IF;
    END PROCESS matchInstruction;
    executeInstruction : PROCESS (SH2Clock)
        -- Set default instruction-specific control signals
        -- Does not include PMAU and address/data bus setting logic, because that is determined
        -- by the state machine

        VARIABLE FlagUpdate : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');
        VARIABLE SignExtBus : STD_LOGIC_VECTOR(regLen - 1 DOWNTO 0) := (OTHERS => '0');

        PROCEDURE SetDefaultExecuteSignals IS
        BEGIN
            -- Default RegArray inputs: Do not input any registers, 
            SH2RegIn <= REG_LEN_ZEROES;
            SH2RegInSel <= REG_ZEROTH_SEL;
            SH2RegStore <= REG_NO_STORE;

            SH2RegAxIn <= REG_LEN_ZEROES;
            SH2RegAxInSel <= REG_ZEROTH_SEL;
            SH2RegAxStore <= REG_NO_STORE;

        END PROCEDURE;

        -- Make sure SH2RegIn is taking the correct byte from the SH2DataBus
        PROCEDURE ReadBSetSH2RegIn IS
        BEGIN
            CASE DMAUAddressIndex IS
                WHEN 0 => -- Grab highest byte
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(31 DOWNTO 24)), regLen)); -- sign-extended data bus value
                WHEN 1 => -- Grab second highest byte
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(23 DOWNTO 16)), regLen)); -- sign-extended data bus value
                WHEN 2 => -- Grab second lowest byte
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(15 DOWNTO 8)), regLen)); -- sign-extended data bus value
                WHEN 3 => -- Grab lowest byte
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(7 DOWNTO 0)), regLen)); -- sign-extended data bus value
                WHEN OTHERS =>
                    -- should never get here
            END CASE;
        END PROCEDURE;

        -- Make sure SH2RegIn is taking the correct word from the SH2DataBus
        PROCEDURE ReadWSetSH2RegIn IS
        BEGIN
            CASE DMAUAddressIndex IS
                WHEN 0 => -- Grab highest word
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(31 DOWNTO 16)), regLen)); -- sign-extended data bus value
                WHEN 1 => -- Grab middle word
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(23 DOWNTO 8)), regLen)); -- sign-extended data bus value
                WHEN 2 => -- Grab lowest word
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(SH2DataBus(15 DOWNTO 0)), regLen)); -- sign-extended data bus value
                WHEN OTHERS =>
                    -- should never get here
            END CASE;
        END PROCEDURE;

    BEGIN

        IF rising_edge(SH2Clock) THEN
            LatchedClockTwo <= ClockTwo;
            LatchedClockThree <= ClockThree;
            LatchedPipelineHalt <= PipelineHalt;
        END IF;

        IF CurrentState = FETCH_IR AND rising_edge(SH2Clock) THEN

            IF (LatchedPipelineHalt = NO_PIPELINE_HALT) THEN

                SetDefaultExecuteSignals;
                --  ==================================================================================================
                -- ARITHMETIC
                -- ==================================================================================================
                IF std_match(InstructionReg, ADD_imm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(InstructionReg, ADD_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(InstructionReg, ADDC_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                    FlagUpdate := RegArrayOutA1;

                    FlagUpdate(0) := NOT FlagBus(FLAG_INDEX_CARRYOUT); --Load into Status Register the new Carryout
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                ELSIF std_match(InstructionReg, ADDV_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                    FlagUpdate := RegArrayOutA1;

                    FlagUpdate(0) := NOT FlagBus(FLAG_INDEX_OVERFLOW); --Load into Status Register the new Carryout
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value                                 --Actually write 

                ELSIF std_match(InstructionReg, SUB_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(InstructionReg, SUBC_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                    FlagUpdate := RegArrayOutA1;

                    FlagUpdate(0) := NOT FlagBus(FLAG_INDEX_CARRYOUT); --Load into Status Register the new Carryout
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value                                         --Actually write 

                ELSIF std_match(InstructionReg, SUBV_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write 

                    FlagUpdate := RegArrayOutA1;

                    FlagUpdate(0) := NOT FlagBus(FLAG_INDEX_OVERFLOW); --Load into Status Register the new Carryout
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value                                            --Actually write 

                ELSIF std_match(InstructionReg, NEG_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Update the value    
                ELSIF std_match(InstructionReg, NEGC_Rm_Rn) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Update the value

                    FlagUpdate := RegArrayOutA1;

                    FlagUpdate(0) := NOT FlagBus(FLAG_INDEX_CARRYOUT); --Load into Status Register the new Carryout
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value   

                ELSIF std_match(InstructionReg, EXTU_B_Rm_Rn) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(InstructionReg, EXTU_W_Rm_Rn) THEN

                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(InstructionReg, EXTS_B_Rm_Rn) THEN
                    SignExtBus := (regLen - 1 DOWNTO 8 => SH2ALUResult(7)) & SH2ALUResult(7 DOWNTO 0);
                    SH2RegIn <= SignExtBus; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(InstructionReg, EXTS_W_Rm_Rn) THEN
                    SignExtBus := (regLen - 1 DOWNTO 16 => SH2ALUResult(15)) & SH2ALUResult(15 DOWNTO 0);
                    SH2RegIn <= SignExtBus; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(InstructionReg, DT_Rn) THEN
                    IF std_match(SH2ALUResult, ALU_ZERO_IMM) THEN
                        SH2RegIn <= RegArrayOutA1(regLen - 1 DOWNTO 1) & '1';
                        SH2RegInSel <= REG_SR;
                        SH2RegStore <= REG_STORE;
                    ELSE
                        SH2RegIn <= RegArrayOutA1(regLen - 1 DOWNTO 1) & '0';
                        SH2RegInSel <= REG_SR;
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_EQ_imm_R0) THEN
                    IF std_match(SH2ALUResult, ALU_ZERO_IMM) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_EQ_Rm_Rn) THEN
                    IF std_match(SH2ALUResult, ALU_ZERO_IMM) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_GE_Rm_Rn) THEN
                    IF (std_match(SH2ALUResult, ALU_ZERO_IMM) OR (SH2ALUResult(regLen - 1) = '0')) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_GT_Rm_Rn) THEN
                    IF ((SH2ALUResult(regLen - 1) = '0') AND (SH2ALUResult /= ALU_ZERO_IMM)) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_HI_Rm_Rn) THEN
                    IF ((NOT FlagBus(FLAG_INDEX_CARRYOUT) = '1') AND (SH2ALUResult /= ALU_ZERO_IMM)) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_HS_Rm_Rn) THEN
                    IF (std_match(SH2ALUResult, ALU_ZERO_IMM) OR (NOT FlagBus(FLAG_INDEX_CARRYOUT) = '1')) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_PL_Rn) THEN
                    IF ((NOT FlagBus(FLAG_INDEX_CARRYOUT) = '1') AND (SH2ALUResult /= ALU_ZERO_IMM)) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_PZ_Rn) THEN
                    IF (std_match(SH2ALUResult, ALU_ZERO_IMM) OR (NOT FlagBus(FLAG_INDEX_CARRYOUT) = '1')) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                ELSIF std_match(InstructionReg, CMP_STR_Rm_Rn) THEN
                    IF (std_match(SH2ALUResult(7 DOWNTO 0), ALU_ZERO_IMM(7 DOWNTO 0)) OR
                        std_match(SH2ALUResult(15 DOWNTO 8), ALU_ZERO_IMM(7 DOWNTO 0)) OR
                        std_match(SH2ALUResult(23 DOWNTO 16), ALU_ZERO_IMM(7 DOWNTO 0)) OR
                        std_match(SH2ALUResult(regLen - 1 DOWNTO 24), ALU_ZERO_IMM(7 DOWNTO 0))) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    ELSE
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '0';

                        SH2RegIn <= FlagUpdate; --Set what data needs to be written
                        SH2RegInSel <= REG_SR; --Set the register to write to (Rn)
                        SH2RegStore <= REG_STORE;
                    END IF;
                    --  ==================================================================================================
                    -- SHIFTS (0/8) : Needs testing
                    --  ==================================================================================================

                ELSIF std_match(SHLL_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(regLen - 1); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                ELSIF std_match(SHLR_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(0); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                ELSIF std_match(SHAR_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(0); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                ELSIF std_match(SHAL_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(regLen - 1); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                ELSIF std_match(ROTCL_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(regLen - 1); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value                                          --Update the value   

                ELSIF std_match(ROTCR_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(0); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                ELSIF std_match(ROTL_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(regLen - 1); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value               

                ELSIF std_match(ROTR_Rn, InstructionReg) THEN
                    -- Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Set the register to write to (Rn)
                    SH2RegStore <= REG_STORE; --Actually write

                    FlagUpdate := RegArrayOutA2;

                    FlagUpdate(0) := RegArrayOutA(0); --Update the T-bit with the high bit value of Rn  
                    SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register   
                    SH2RegAxInSel <= REG_SR; --Write back at the Status Register index
                    SH2RegAxStore <= REG_STORE; --Update the value  

                    --  ==================================================================================================
                    -- LOGICAL 0/9 Needs testing
                    --  ==================================================================================================
                ELSIF std_match(AND_Rm_Rn, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(AND_imm_R0, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= REG_ZEROTH_SEL;
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(TST_Rm_Rn, InstructionReg) THEN
                    IF std_match(SH2ALUResult, REG_LEN_ZEROES) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1'; --Load into Status Register the new Carryout
                        SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register 
                        SH2RegAxInSel <= REG_SR;
                        SH2RegAxStore <= REG_STORE;
                    END IF;

                ELSIF std_match(TST_imm_R0, InstructionReg) THEN
                    IF std_match(SH2ALUResult, REG_LEN_ZEROES) THEN
                        FlagUpdate := RegArrayOutA1;
                        FlagUpdate(0) := '1'; --Load into Status Register the new Carryout
                        SH2RegAxIn <= FlagUpdate; --Write back in Ax which is the Status Register 
                        SH2RegAxInSel <= REG_SR;
                        SH2RegAxStore <= REG_STORE;
                    END IF;

                ELSIF std_match(OR_Rm_Rn, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(OR_imm_R0, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= REG_ZEROTH_SEL;
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(XOR_Rm_Rn, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(XOR_imm_R0, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= REG_ZEROTH_SEL;
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(NOT_Rm_Rn, InstructionReg) THEN
                    --Setting Reg Array control signals
                    SH2RegIn <= SH2ALUResult;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8)));
                    SH2RegStore <= REG_STORE;

                    --  ==================================================================================================
                    -- LOAD
                    --  ==================================================================================================

                    -- Load immediate
                ELSIF std_match(MOV_IMM_TO_Rn, InstructionReg) THEN

                    -- Store immediate data into Rn
                    SH2RegIn <= STD_LOGIC_VECTOR(resize(signed(InstructionReg(7 DOWNTO 0)), regLen)); -- sign-extended immediate
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Load from reg address directly
                ELSIF std_match(MOVB_atRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadBSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVW_atRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadWSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVL_atRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    SH2RegIn <= SH2DataBus;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Load from reg address + reg address in R0
                ELSIF std_match(MOVB_atR0Rm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into R0
                    ReadBSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVW_atR0Rm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into R0
                    ReadWSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVL_atR0Rm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    SH2RegIn <= SH2DataBus;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Load from reg address post-incremented
                ELSIF std_match(MOVB_atPostIncRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadBSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Store new calculated address into Rm
                    SH2RegAxIn <= DMAUPostIncDecSrc;
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Store inside register Rm
                    SH2RegAxStore <= REG_STORE;

                ELSIF std_match(MOVW_atPostIncRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadWSetSH2RegIn;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Store new calculated address into Rm
                    SH2RegAxIn <= DMAUPostIncDecSrc;
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Store inside register Rm
                    SH2RegAxStore <= REG_STORE;

                ELSIF std_match(MOVL_atPostIncRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    SH2RegIn <= SH2DataBus;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Store new calculated address into Rm
                    SH2RegAxIn <= DMAUPostIncDecSrc;
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(7 DOWNTO 4))); -- Store inside register Rm
                    SH2RegAxStore <= REG_STORE;

                    -- Load from disp * (1,2,4) + reg address (into R0 or Rn)
                ELSIF std_match(MOVB_atDispRm_TO_R0, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadBSetSH2RegIn;
                    SH2RegInSel <= 0; -- Store inside register R0
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVW_atDispRm_TO_R0, InstructionReg) THEN

                    -- Store data bus data into Rn
                    ReadWSetSH2RegIn;
                    SH2RegInSel <= 0; -- Store inside register R0
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOVL_atDispRm_TO_Rn, InstructionReg) THEN

                    -- Store data bus data into Rn
                    SH2RegIn <= SH2DataBus;
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn (at index n)
                    SH2RegStore <= REG_STORE;

                    -- Load from dis * (1,2,4) + GBR (into R0)
                ELSIF std_match(MOV_B_R0_GBR, InstructionReg) THEN
                    -- Store data bus data into R0
                    ReadBSetSH2RegIn;
                    SH2RegInSel <= 0; -- Store inside register R0
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOV_W_R0_GBR, InstructionReg) THEN

                    -- Store data bus data into R0
                    ReadWSetSH2RegIn;
                    SH2RegInSel <= 0; -- Store inside register R0
                    SH2RegStore <= REG_STORE;

                ELSIF std_match(MOV_L_R0_GBR, InstructionReg) THEN

                    -- Store data bus data into R0
                    SH2RegIn <= SH2DataBus; -- sign-extended data bus value
                    SH2RegInSel <= 0; -- Store inside register R0
                    SH2RegStore <= REG_STORE;

                    --  ==================================================================================================
                    -- STORE
                    --  ==================================================================================================

                    -- Store value in Rm to RAM address in Rn
                ELSIF std_match(MOVB_Rm_TO_atRn, InstructionReg) THEN
                ELSIF std_match(MOVW_Rm_TO_atRn, InstructionReg) THEN
                ELSIF std_match(MOVL_Rm_TO_atRn, InstructionReg) THEN

                    -- Store value in Rm to (RAM address in Rn + RAM address in R0)
                ELSIF std_match(MOVB_Rm_TO_atR0Rn, InstructionReg) THEN
                ELSIF std_match(MOVW_Rm_TO_atR0Rn, InstructionReg) THEN
                ELSIF std_match(MOVL_Rm_TO_atR0Rn, InstructionReg) THEN

                    -- Store value in Rm to (pre decremented RAM address in Rn)
                ELSIF std_match(MOVB_Rm_TO_atPreDecRn, InstructionReg) THEN

                    -- Update Rn with pre-decremented address
                    SH2RegAxIn <= SH2CalculatedDataAddress; -- address has been incremented
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn
                    SH2RegAxStore <= REG_STORE;

                ELSIF std_match(MOVW_Rm_TO_atPreDecRn, InstructionReg) THEN

                    -- Update Rn with pre-decremented address
                    SH2RegAxIn <= SH2CalculatedDataAddress; -- address has been incremented
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn
                    SH2RegAxStore <= REG_STORE;

                ELSIF std_match(MOVL_Rm_TO_atPreDecRn, InstructionReg) THEN

                    -- Update Rn with pre-decremented address
                    SH2RegAxIn <= SH2CalculatedDataAddress; -- address has been incremented
                    SH2RegAxInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rn
                    SH2RegAxStore <= REG_STORE;

                    -- Store value in R0 to ((RAM address in Rn) + (1,2,4)*disp)
                ELSIF std_match(MOVB_R0_TO_atDispRn, InstructionReg) THEN
                ELSIF std_match(MOVW_R0_TO_atDispRn, InstructionReg) THEN
                ELSIF std_match(MOVL_Rm_TO_atDispRn, InstructionReg) THEN

                    -- Store value in R0 to ((RAM address in Rn) + (1,2,4)*GBR)
                ELSIF std_match(MOV_B_GBR_R0, InstructionReg) THEN
                ELSIF std_match(MOV_W_GBR_R0, InstructionReg) THEN
                ELSIF std_match(MOV_L_GBR_R0, InstructionReg) THEN

                    --========================================
                    -- System control
                    --========================================
                ELSIF std_match(SETT, InstructionReg) THEN
                    FlagUpdate := SH2ALUResult;
                    FlagUpdate(0) := '1';
                    SH2RegIn <= FlagUpdate; --Set what data needs to be written
                    SH2RegInSel <= REG_SR; --Write back to the status register
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(LDC_Rm_SR, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= REG_SR; --Write back to the status register
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(STC_SR_Rn, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Write back to the Rn
                    SH2RegStore <= REG_STORE; --Actually write 
                ELSIF std_match(STC_GBR_Rn, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Write back to the Rn
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(STC_VBR_Rn, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Write back to the Rn
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(STS_PR_Rn, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); --Write back to the Rn
                    SH2RegStore <= REG_STORE; --Actually write 
                ELSIF std_match(LDC_Rm_GBR, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= REG_GBR; --Write back to the GBR
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(LDC_Rm_VBR, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= REG_VBR; --Write back to the VBR
                    SH2RegStore <= REG_STORE; --Actually write 

                ELSIF std_match(LDS_Rm_PR, InstructionReg) THEN
                    SH2RegIn <= SH2ALUResult; --Set what data needs to be written
                    SH2RegInSel <= REG_PR; --Write back to the PR
                    SH2RegStore <= REG_STORE; --Actually write 
                ELSIF std_match(JSR_Rm, InstructionReg) THEN
                    SH2RegIn <= StorePC; --Set what data needs to be written
                    SH2RegInSel <= REG_PR; --Write back to the PR
                    SH2RegStore <= REG_STORE; --Actually write 
                ELSIF std_match(BSR_disp, InstructionReg) THEN
                    SH2RegIn <= StorePC; --Set what data needs to be written
                    SH2RegInSel <= REG_PR; --Write back to the PR
                    SH2RegStore <= REG_STORE; --Actually write 
                ELSIF std_match(BSRF_Rm, InstructionReg) THEN
                    SH2RegIn <= StorePC; --Set what data needs to be written
                    SH2RegInSel <= REG_PR; --Write back to the PR
                    SH2RegStore <= REG_STORE; --Actually write 
                    -- ================================
                    -- System Register Control
                    -- =================================
                END IF;
            END IF;

                --===============================================
                -- Instructions that can run during pipeline halt
                --================================================
            IF std_match(STC_L_SR_Rn, MultiClockReg) AND ClockTwo = '1' THEN
                -- Update Rn with pre-decremented address
                SH2RegAxIn <= SH2CalculatedDataAddress; -- address has been incremented
                SH2RegAxInSel <= to_integer(unsigned(MultiClockReg(11 DOWNTO 8))); -- Store inside register Rn
                SH2RegAxStore <= REG_STORE;

            ELSIF std_match(LDC_L_Rm_SR, MultiClockReg) AND ClockTwo = '1' THEN
                -- Update SR with loaded-from-memory value
                -- Store data bus data into Rn
                SH2RegIn <= SH2DataBus and SR_MASK;
                SH2RegInSel <= REG_SR; -- Store inside SR
                SH2RegStore <= REG_STORE;

                -- Store new calculated address into Rm
                SH2RegAxIn <= DMAUPostIncDecSrc;
                SH2RegAxInSel <= to_integer(unsigned(InstructionReg(11 DOWNTO 8))); -- Store inside register Rm
                SH2RegAxStore <= REG_STORE;
            END IF;


        END IF;
    END PROCESS executeInstruction;
    ------------------------------------------------------------------------------------------------------ Combinationally-updating signals

    --- DMAU write things: need to combinationally update to update in time for execution on the falling edge of the clock --
    DMAUAddressIndex <= to_integer(unsigned(SH2CalculatedDataAddress(1 DOWNTO 0)));

    -- Make sure low byte of Rm is put in the place where we memory will be reading it from!
    -- recall, stores read the value to store from HoldRegA2, so we'll modify that
    updateDataBusForWrite : PROCESS (WriteToMemoryB, WriteToMemoryW, DMAUAddressIndex, RegArrayOutA2)
    BEGIN
        -- Default assignment when a full word
        HoldRegA2 <= RegArrayOutA2;

        -- Byte write case
        IF WriteToMemoryB = WRITE_TO_MEMORY THEN
            CASE DMAUAddressIndex IS
                WHEN 0 =>
                    HoldRegA2(31 DOWNTO 24) <= RegArrayOutA2(7 DOWNTO 0);
                WHEN 1 =>
                    HoldRegA2(23 DOWNTO 16) <= RegArrayOutA2(7 DOWNTO 0);
                WHEN 2 =>
                    HoldRegA2(15 DOWNTO 8) <= RegArrayOutA2(7 DOWNTO 0);
                WHEN 3 =>
                    HoldRegA2(7 DOWNTO 0) <= RegArrayOutA2(7 DOWNTO 0);
                WHEN OTHERS =>
                    NULL; -- no operation
            END CASE;

            -- Word write case
        ELSIF WriteToMemoryW = WRITE_TO_MEMORY THEN
            CASE DMAUAddressIndex IS
                WHEN 0 =>
                    HoldRegA2(31 DOWNTO 16) <= RegArrayOutA2(15 DOWNTO 0);
                WHEN 1 =>
                    HoldRegA2(23 DOWNTO 8) <= RegArrayOutA2(15 DOWNTO 0);
                WHEN 2 =>
                    HoldRegA2(15 DOWNTO 0) <= RegArrayOutA2(15 DOWNTO 0);
                WHEN OTHERS =>
                    NULL; -- no operation
            END CASE;
        END IF;
    END PROCESS updateDataBusForWrite;
    ------------------------

    -- Set buses (This is combinational, outside of any clocked process.)
    SH2DataBus <= SH2DataBus WHEN SH2SelDataBus = HOLD_DATA_BUS ELSE
        HoldRegA2 WHEN SH2SelDataBus = SET_DATA_BUS_TO_REG_A2_OUT ELSE
        SH2ALUResult WHEN SH2SelDataBus = SET_DATA_BUS_TO_ALU_OUT ELSE
        (OTHERS => 'Z');

    -- Note: We multiply the PC by 4 because each 32 memory block is 4 addresses apart
    SH2AddressBus <= SH2AddressBus WHEN SH2SelAddressBus = HOLD_ADDRESS_BUS ELSE
        SH2CalculatedDataAddress WHEN SH2SelAddressBus = SET_ADDRESS_BUS_TO_DMAU_OUT ELSE
        STD_LOGIC_VECTOR(to_unsigned(4 * to_integer(unsigned(SH2PC)), SH2AddressBus'length)) WHEN SH2SelAddressBus = SET_ADDRESS_BUS_TO_PMAU_OUT ELSE
        (OTHERS => 'Z');
    -- Make instruction reg combinational so that it updates immediately
    InstructionReg <= SH2DataBus(instrLen - 1 DOWNTO 0)
        WHEN SH2Clock = '1'
        ELSE
        InstructionReg;
END Structural;