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
----------------------------------------------------------------------------

------------------------------------------------- Constants
library ieee;
use ieee.std_logic_1164.ALL;
package SH2_CPU_Constants is

    -- Register and word size configuration
    constant regLen       : integer := 32;   -- Each register is 32 bits
    constant regCount     : integer := 21;   -- 16 general + 5 special registers

    -- DMAU configuration
    constant dmauSourceCount  : integer := 2;    -- from reg array (Register, GBR, PC) or immediate
    constant dmauOffsetCount  : integer := 7;    -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    constant maxIncDecBitDMAU     : integer := 3;    -- Allow inc/dec up to bit 3 (+-4)

    -- PMAU configuration
    constant pmauSourceCount  : integer := 2;    -- from reg array (PC) or immediate
    constant pmauOffsetCount  : integer := 7;    -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
    constant maxIncDecBitPMAU     : integer := 3;    -- Allow inc/dec up to bit 3 (+-4)

    -- Flag bit positions (useful for flag bus indexing)
    constant FLAG_INDEX_CARRYOUT     : integer := 4;
    constant FLAG_INDEX_HALF_CARRY   : integer := 3;
    constant FLAG_INDEX_OVERFLOW     : integer := 2;
    constant FLAG_INDEX_ZERO         : integer := 1;
    constant FLAG_INDEX_SIGN         : integer := 0;

    -- Special register indices
    constant REG_GBR           : integer := 16;
    constant REG_VBR           : integer := 17;
    constant REG_PR            : integer := 18;
    constant REG_PC            : integer := 19;
    constant REG_SR            : integer := 20;

    -- Choosing data and address bus indicies
    constant NUM_DATA_BUS_OPTIONS : integer := 2; -- ALU, regs
    constant NUM_ADDRESS_BUS_OPTIONS : integer := 2; -- DMAU, PMAU
    constant HOLD_DATA_BUS : integer := 0;
    constant SET_DATA_BUS_TO_REG_A_OUT : integer := 1;
    constant SET_DATA_BUS_TO_ALU_OUT : integer := 2;
    constant HOLD_ADDRESS_BUS : integer := 0;
    constant SET_ADDRESS_BUS_TO_PMAU_OUT : integer := 1;
    constant SET_ADDRESS_BUS_TO_DMAU_OUT : integer := 2;

end SH2_CPU_Constants;

library ieee;
use ieee.std_logic_1164.ALL;
package SH2_IR_Constants is
    --Decoded Constants
    --Took the high byte and used it to decode
    --Used the lower bytes to differentiate the commands

    --PINK
    constant LOGICAL_CMP_TWO_REG_XTRACT :   std_logic_vector(3 downto 0)    := "0010";
    --sub-pink category codes
    --check the lowest byte against these
    constant AND_TWO_REG                :   std_logic_vector(3 downto 0)    := "1001";
    constant OR_TWO_REG                 :   std_logic_vector(3 downto 0)    := "1011";
    constant TST_TWO_REG                :   std_logic_vector(3 downto 0)    := "1000";
    constant XOR_TWO_REG                :   std_logic_vector(3 downto 0)    := "1010";

    constant XTRCT                      :   std_logic_vector(3 downto 0)    := "1101";

    constant CMP_STR                    :   std_logic_vector(3 downto 0)    := "1100";

    --BLUE
    constant LOGICAL_IMM_MOV_DISP       :   std_logic_vector(3 downto 0)    := "1100";
    --sub-blue category codes
    --check these against the next highest byte after the highest one
    constant AND_IMM                    :   std_logic_vector(3 downto 0)    := "1001";
    constant AND_B                      :   std_logic_vector(3 downto 0)    := "1101";
    constant OR_IMM                     :   std_logic_vector(3 downto 0)    := "1011";
    constant OR_B                       :   std_logic_vector(3 downto 0)    := "1111";
    constant TST_IMM                    :   std_logic_vector(3 downto 0)    := "1000";
    constant TST_B                      :   std_logic_vector(3 downto 0)    := "1100";
    constant XOR_IMM                    :   std_logic_vector(3 downto 0)    := "1010";
    constant XOR_B                      :   std_logic_vector(3 downto 0)    := "1110";

    constant MOV_B_R0                   :   std_logic_vector(3 downto 0)    := "0000";
    constant MOV_W_R0                   :   std_logic_vector(3 downto 0)    := "0001";
    constant MOV_L_R0                   :   std_logic_vector(3 downto 0)    := "0010";
    constant MOV_B_GBR                  :   std_logic_vector(3 downto 0)    := "0100";
    constant MOV_W_GBR                  :   std_logic_vector(3 downto 0)    := "0101";
    constant MOV_L_GBR                  :   std_logic_vector(3 downto 0)    := "0110";
    constant MOVA                       :   std_logic_vector(3 downto 0)    := "0111";


    --PURPLE
    constant SHIFT_JMP_JSR_LD_STC       :  std_logic_vector(3 downto 0)    := "0100";
    --sub-purple category codes
    --check these against the lowest bits
    constant JMP                        :   std_logic_vector(7 downto 0)    := "00101011";
    constant JSR                        :   std_logic_vector(7 downto 0)    := "00001011";

    constant ROTL                       :   std_logic_vector(7 downto 0)    := "00000100";
    constant ROTR                       :   std_logic_vector(7 downto 0)    := "00000101";
    constant ROTCL                      :   std_logic_vector(7 downto 0)    := "00100100";
    constant ROTCR                      :   std_logic_vector(7 downto 0)    := "00100101";
    constant SHAL                       :   std_logic_vector(7 downto 0)    := "00100000";
    constant SHAR                       :   std_logic_vector(7 downto 0)    := "00100001";
    constant SHLL                       :   std_logic_vector(7 downto 0)    := "00000000";
    constant SHLR                       :   std_logic_vector(7 downto 0)    := "00000001";

    constant CMP_PL                     :   std_logic_vector(7 downto 0)    := "00010101";
    constant CMP_PZ                     :   std_logic_vector(7 downto 0)    := "00010001";
    constant DL                         :   std_logic_vector(7 downto 0)    := "00010000";

    constant LDC_SR                     :   std_logic_vector(7 downto 0)    := "00001110";
    constant LDC_GBR                    :   std_logic_vector(7 downto 0)    := "00011110";
    constant LDC_VBR                    :   std_logic_vector(7 downto 0)    := "00101110";
    constant LDC_L_SR                   :   std_logic_vector(7 downto 0)    := "00000111";
    constant LDC_L_GBR                  :   std_logic_vector(7 downto 0)    := "00010111";
    constant LDC_L_VBR                  :   std_logic_vector(7 downto 0)    := "00100111";
    constant LDS_PR                     :   std_logic_vector(7 downto 0)    := "00100110";
    constant LDS_L_PR                   :   std_logic_vector(7 downto 0)    := "00100110";
    constant STC_L_SR                   :   std_logic_vector(7 downto 0)    := "00000011";
    constant STC_L_GBR                  :   std_logic_vector(7 downto 0)    := "00010011";
    constant STC_L_VBR                  :   std_logic_vector(7 downto 0)    := "00100010";
    constant STS_L_PR                   :   std_logic_vector(7 downto 0)    := "00100011";

    --PALE PINK    
    constant NOT_SWAP_EXTU_EXTS_NEG     :   std_logic_vector(3 downto 0)    := "0110";
    --sub-pale pink category codes
    --check the lowest byte against these
    constant NOT_CMD                    :   std_logic_vector(3 downto 0)    := "0111";

    constant SWAP_B                     :   std_logic_vector(3 downto 0)    := "1000";
    constant SWAP_W                     :   std_logic_vector(3 downto 0)    := "1001";

    constant EXTU_B                     :   std_logic_vector(3 downto 0)    := "1100";
    constant EXTU_W                     :   std_logic_vector(3 downto 0)    := "1101";
    constant EXTS_B                     :   std_logic_vector(3 downto 0)    := "1110";
    constant EXTS_W                     :   std_logic_vector(3 downto 0)    := "1111";
    constant NEG                        :   std_logic_vector(3 downto 0)    := "1011";
    constant NEG_CARRY                  :   std_logic_vector(3 downto 0)    := "1010";

    --LIGHT GREEN
    constant BF_BT_LABLE_CMP_EQ         :   std_logic_vector(3 downto 0)    := "1000";
    --sub-light green category codes
    --check the NEXT highest byte after the highest byte
    constant BF_LABEL                   :   std_logic_vector(3 downto 0)    := "1011";
    constant BF_S_LABEL                 :   std_logic_vector(3 downto 0)    := "1111";
    constant BT_LABEL                   :   std_logic_vector(3 downto 0)    := "1001";
    constant BT_S_LABEL                 :   std_logic_vector(3 downto 0)    := "1101";

    constant CMP_EQ_R0                  :   std_logic_vector(3 downto 0)    := "1000";

    --GREEN
    constant BRAF_BRSF_MOV_REG_MOVT_STCS_RN :   std_logic_vector(3 downto 0)    := "0000";
    --sub-green category codes
    --check the lowest bits against these
    constant BRAF                       :   std_logic_vector(7 downto 0)    := "00100011";
    constant BSRF                       :   std_logic_vector(7 downto 0)    := "00000011";

    constant MOV_L_RM                   :   std_logic_vector(3 downto 0)    := "0110";
    constant MOV_B_RN                   :   std_logic_vector(3 downto 0)    := "1100";
    constant MOV_W_RN                   :   std_logic_vector(3 downto 0)    := "1101";
    constant MOV_L_RN                   :   std_logic_vector(3 downto 0)    := "1110";
    constant MOVT_RN                    :   std_logic_vector(7 downto 0)    := "00101001";

    constant STC_SR                     :   std_logic_vector(7 downto 0)    := "00000010";
    constant STC_GBR                    :   std_logic_vector(7 downto 0)    := "00010010";
    constant STC_VBR                    :   std_logic_vector(7 downto 0)    := "00100010";
    constant STS_PR                     :   std_logic_vector(7 downto 0)    := "00101010";

    --ORANGE
    constant ADD_SUB_CMP_TWO_REG        :   std_logic_vector(3 downto 0)    := "0011";
    --sub-orange category codes
    --check the lowest byte against these
    constant ADD_TWO_REG                :   std_logic_vector(3 downto 0)    := "1100";
    constant ADD_CARRY_TWO_REG          :   std_logic_vector(3 downto 0)    := "1110";
    constant ADD_OVERFLOW_TWO_REG       :   std_logic_vector(3 downto 0)    := "1111";

    constant CMP_EQ_TWO_REG             :   std_logic_vector(3 downto 0)    := "0000";
    constant CMP_HS_TWO_REG             :   std_logic_vector(3 downto 0)    := "0010";
    constant CMP_GE_TWO_REG             :   std_logic_vector(3 downto 0)    := "0011";
    constant CMP_HI_TWO_REG             :   std_logic_vector(3 downto 0)    := "0110";
    constant CMP_GT_TWO_REG             :   std_logic_vector(3 downto 0)    := "0111";

    constant SUB_TWO_REG                :   std_logic_vector(3 downto 0)    := "1000";
    constant SUB_CARRY_TWO_REG          :   std_logic_vector(3 downto 0)    := "1010";
    constant SUB_OVERFLOW_TWO_REG       :   std_logic_vector(3 downto 0)    := "1011";

    --RED
    constant CLRT                       :   std_logic_vector(3 downto 0)    := "1000";
    constant TRAPA                      :   std_logic_vector(6 downto 0)    := "1100011";
    constant NOP                        :   std_logic_vector(3 downto 0)    := "1001";
    constant SETT                       :   std_logic_vector(4 downto 0)    := "11000";
    constant SLEEP                      :   std_logic_vector(4 downto 0)    := "11011";
    constant ADD_IMM                    :   std_logic_vector(3 downto 0)    := "0111";
    constant BRA_LABEL                  :   std_logic_vector(3 downto 0)    := "1010";
    --BSR has same opcode to check, but is a longer vector than RTS
    constant BSR_LABEL                  :   std_logic_vector(3 downto 0)    := "1011";
    constant RTS                        :   std_logic_vector(3 downto 0)    := "1011";
end SH2_IR_Constants;

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
package array_type_pkg is
   --  a 2D array of std_logic (VHDL-2008)
   type  std_logic_array  is  array (natural range<>) of std_logic_vector;

end package;

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.SH2_CPU_Constants.all;
use work.SH2_IR_Constants.all;
use work.array_type_pkg.all;


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
    ------------------------------------------------------------------------------------------------------------------
    -- REG ARRAY FROM CONTROL UNIT INPUTS (for selecting reg in/out control)
    signal SH2RegIn      : std_logic_vector(regLen - 1 downto 0);
    signal SH2RegInSel   : integer  range regCount - 1 downto 0;
    signal SH2RegStore   : std_logic;
    signal SH2RegASel    : integer  range regCount - 1 downto 0;
    signal SH2RegBSel    : integer  range regCount - 1 downto 0;
    signal SH2RegAx : std_logic_vector(regLen - 1 downto 0);
    signal SH2RegAxIn    : std_logic_vector(regLen - 1 downto 0);
    signal SH2RegAxInSel : integer  range regCount - 1 downto 0;
    signal SH2RegAxStore : std_logic;
    signal SH2RegA1Sel   : integer  range regCount - 1 downto 0;
    signal SH2RegA2Sel   : integer  range regCount - 1 downto 0;
    ------------------------------------------------------------------------------------------------------------------
    -- ALU FROM CONTROL UNIT INPUTS (for ALU operation control)
    signal SH2FCmd     : std_logic_vector(3 downto 0);              -- F-Block operation
    signal SH2CinCmd   : std_logic_vector(1 downto 0);              -- carry in operation
    signal SH2SCmd     : std_logic_vector(2 downto 0);              -- shift operation
    signal SH2ALUCmd   : std_logic_vector(1 downto 0);              -- ALU result select
    -- ALU additional from control line inputs (not directly from generic ALU)
    signal SH2ALUImmediateOperand : std_logic_vector(regLen-1 downto 0);    -- control unit should pad it (with 1s or 0s
                                                                     -- based on whether it's signed or not)
                                                                     -- before giving us immediate operand
    signal SH2ALUUseImmediateOperand : std_logic_vector(regLen-1 downto 0); -- 1 for use immediate operand, 0 otherwise
    -- ALU OUTPUTS
    signal SH2ALUResult   : std_logic_vector(regLen - 1 downto 0);   -- ALU result
    signal FlagBus : std_logic_vector(4 downto 0); -- Flags are Cout, HalfCout, Overflow, Zero, Sign
    ------------------------------------------------------------------------------------------------------------------
    -- DMAU FROM CONTROL LINE INPUTS
    signal SH2DMAUSrcSel     : integer  range dmauSourceCount - 1 downto 0;
    signal SH2DMAUOffsetSel  : integer  range dmauOffsetCount - 1 downto 0;
    signal SH2DMAUIncDecSel  : std_logic;
    signal SH2DMAUIncDecBit  : integer  range maxIncDecBitDMAU downto 0;
    signal SH2DMAUPrePostSel : std_logic;
    -- DMAU added inputs (not directly from generic MAU)
    signal DMAUImmediateSource :  std_logic_vector(regLen-1 downto 0);
    signal DMAUImmediateOffset :  std_logic_vector(regLen-1 downto 0);
    -- DMAU OUTPUTS
    signal SH2DataAddressBus :   std_logic_vector(regLen - 1 downto 0);   -- DMAU input address, updated
                                                                            -- (Need control line to see which src)
    signal SH2DataAddressSrc :   std_logic_vector(regLen - 1 downto 0);   -- DMAU input address, updated
    -- (Need control line to see which src)
    -------------------------------------------------------------------------------------
    -- PMAU FROM CONTROL LINE INPUTS
    signal SH2PMAUSrcSel     : integer  range pmauSourceCount - 1 downto 0;
    signal SH2PMAUOffsetSel  : integer  range pmauOffsetCount - 1 downto 0;
    signal SH2PMAUIncDecSel  : std_logic;
    signal SH2PMAUIncDecBit  : integer  range maxIncDecBitPMAU downto 0;
    signal SH2PMAUPrePostSel : std_logic;
    -- PMAU added inputs (not directly from generic MAU)
    signal PMAUImmediateSource : std_logic_vector(regLen-1 downto 0);
    signal PMAUImmediateOffset : std_logic_vector(regLen-1 downto 0);
    -- PMAU OUTPUTS
    signal SH2ProgramAddressBus : std_logic_vector(regLen - 1 downto 0);   -- PMAU input address, updated
                                                                            -- (Control unit uses to update PC)
    signal SH2ProgramAddressSrc : std_logic_vector(regLen - 1 downto 0);   -- PMAU input address, updated
                                                                            -- (Control unit uses to update PC) 
    ------------------------------------------------------------------------------------------
    -- CONTROL OUTPUTS
    signal SH2SelDataBus : integer range NUM_DATA_BUS_OPTIONS downto 0; -- do not update, update with reg output, or update with ALU output
    signal SH2SelAddressBus : integer range NUM_ADDRESS_BUS_OPTIONS downto 0; -- do not update, update with PMAU address out, or update with DMAU address out

    -- Outputs of registers; get hooked up to ALU and PMAU and DMAU
    signal RegArrayOutA : std_logic_vector(regLen - 1 downto 0);
    signal RegArrayOutB : std_logic_vector(regLen - 1 downto 0);
    signal RegArrayOutA1 : std_logic_vector(regLen - 1 downto 0);
    signal RegArrayOutA2 : std_logic_vector(regLen - 1 downto 0);

begin

    -- Instantiate memory unit
    SH2ExternalMemory : entity work.MEMORY32x32
        generic map (
            MEMSIZE     => 256,
            START_ADDR0 => 0,
            START_ADDR1 => 256,
            START_ADDR2 => 512,
            START_ADDR3 => 1024
        )
        port map (
            RE0    => RE0,
            RE1    => RE1,
            RE2    => RE2,
            RE3    => RE3, 
            WE0    => WE0, 
            WE1    => WE1, 
            WE2    => WE2, 
            WE3    => WE3, 
            MemAB  => SH2AddressBus, 
            MemDB  => SH2DataBus 
        );

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
            SH2DMAURegSource => RegArrayOutA, 
            SH2DMAUImmediateSource => DMAUImmediateSource, 
            SH2DMAURegOffset => RegArrayOutB, 
            SH2DMAUImmediateOffset => DMAUImmediateOffset, 
            SH2DMAUSrcSel => SH2DMAUSrcSel,
            SH2DMAUOffsetSel => SH2DMAUOffsetSel, 
            SH2DMAUIncDecSel  => SH2DMAUIncDecSel, 
            SH2DMAUIncDecBit  => SH2DMAUIncDecBit, 
            SH2DMAUPrePostSel => SH2DMAUPrePostSel, 
            SH2DataAddressBus => SH2AddressBus,       -- just GBR?
            SH2DataAddressSrc => SH2DataAddressSrc
        );

    -- Instantiate DMAU
    SH2PMAU : entity  work.SH2PMAU
        port map(
            SH2PMAURegSource => RegArrayOutA, 
            SH2PMAUImmediateSource => PMAUImmediateSource, 
            SH2PMAURegOffset => RegArrayOutB, 
            SH2PMAUImmediateOffset => PMAUImmediateOffset, 
            SH2PMAUSrcSel => SH2PMAUSrcSel,
            SH2PMAUOffsetSel => SH2PMAUOffsetSel, 
            SH2PMAUIncDecSel  => SH2PMAUIncDecSel, 
            SH2PMAUIncDecBit  => SH2PMAUIncDecBit, 
            SH2PMAUPrePostSel => SH2PMAUPrePostSel, 
            SH2ProgramAddressBus => RegArrayOutA,        --make the PC come out into here
            SH2ProgramAddressSrc => SH2ProgramAddressSrc
        );

    -- Set buses
    SH2DataBus <= SH2DataBus when SH2SelDataBus = HOLD_DATA_BUS else
        RegArrayOutA when SH2SelDataBus = SET_DATA_BUS_TO_REG_A_OUT else
        SH2ALUResult;

    SH2AddressBus <= SH2AddressBus when SH2SelAddressBus = HOLD_ADDRESS_BUS else
        SH2DataAddressSrc when SH2SelAddressBus = SET_ADDRESS_BUS_TO_DMAU_OUT else
        SH2ProgramAddressSrc;


end Structural;
