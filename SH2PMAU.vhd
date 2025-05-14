----------------------------------------------------------------------------
--
--  SH2 Program Memory Access Unit
--
--  This is an implementation of a Program memory access unit for SH2
--  microprocessors.  This unit generates the memory address for either load
--  and store operations. 
--
--  Packages included are:
--     SH2_CPU_Constants -- all constants for SH2 processor blocks
--  Entities included are:
--     SH2PMAU  - SH2 Program memory access unit
--
--  Revision History:
--     24 Apr 25  Ruth Berkun       Copied over from mau.vhd template
--      3 May 25  Ruth Berkun       Fixed shifting syntax error
--     12 May 25  Ruth Berkun       Move PC into the PMAU (so that regArray doesn't have
--                                  to be constantly outputting PC every clock)
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
package SH2PMAUConstants is

  -- Register and word size configuration
  constant regLen       : integer := 32;   -- Each register is 32 bits
  constant regCount     : integer := 18;   -- 16 general + 2 special registers

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

end package;

use work.SH2PMAUConstants.all;
library ieee;
use ieee.std_logic_1164.all;

entity  SH2PMAU  is
    port(
        SH2PMAUReset : in std_logic;    -- active low: 0 to reset
        SH2PMAURegSource :  in std_logic_vector(regLen-1 downto 0);
        SH2PMAUImmediateSource :  in std_logic_vector(regLen-1 downto 0);
        SH2PMAURegOffset :  in std_logic_vector(regLen-1 downto 0);
        SH2PMAUImmediateOffset :  in std_logic_vector(regLen-1 downto 0);
        SH2PMAUSrcSel     : in      integer  range pmauSourceCount - 1 downto 0;
        SH2PMAUOffsetSel  : in      integer  range pmauOffsetCount - 1 downto 0;
        SH2PMAUIncDecSel  : in      std_logic;
        SH2PMAUIncDecBit  : in      integer  range maxIncDecBitPMAU downto 0;
        SH2PMAUPrePostSel : in      std_logic;
        SH2ProgramAddressBus : out     std_logic_vector(regLen - 1 downto 0)
    );

end  SH2PMAU;

library ieee;
use ieee.std_logic_1164.all;
use work.array_type_pkg.all;

architecture  behavioral  of  SH2PMAU  is

	component  MemUnit
        generic (
            srcCnt       : integer;
            offsetCnt    : integer;
            maxIncDecBit : integer := 0; -- default is only inc/dec bit 0
            wordsize     : integer := 32 -- default address width is 32 bits
        );

        port(
            AddrSrc    : in      std_logic_array(srccnt - 1 downto 0)(wordsize - 1 downto 0);
            SrcSel     : in      integer  range srccnt - 1 downto 0;
            AddrOff    : in      std_logic_array(offsetcnt - 1 downto 0)(wordsize - 1 downto 0);
            OffsetSel  : in      integer  range offsetcnt - 1 downto 0;
            IncDecSel  : in      std_logic;
            IncDecBit  : in      integer  range maxIncDecBit downto 0;
            PrePostSel : in      std_logic;
            Address    : out     std_logic_vector(wordsize - 1 downto 0);
            AddrSrcOut : buffer  std_logic_vector(wordsize - 1 downto 0)
        );
    end component;

    -- PC
    signal SH2PC : std_logic_vector(regLen-1 downto 0) := (others => '0');

    -- PMAU source arrays
    signal SH2PMAUAddrSrc : std_logic_array(pmauSourceCount - 1 downto 0)(regLen - 1 downto 0);
    signal SH2PMAUAddrOff :std_logic_array(pmauOffsetCount - 1 downto 0)(regLen - 1 downto 0);

    -- Intermediates
    signal genericMAUProgramAddressBus : std_logic_vector(regLen-1 downto 0) := (others => '0');

begin

    -- PMAU: Prepare inputs
    -- Fill source array. 
    SH2PMAUAddrSrc(PMAU_SRC_SEL_REG) <= SH2PMAURegSource; --Sources can come from register array
    SH2PMAUAddrSrc(PMAU_SRC_SEL_IMM) <= SH2PMAUImmediateSource; --or be an immediate value from the control unit
    SH2PMAUAddrSrc(PMAU_SRC_SEL_PC) <= SH2PC; -- or PC 

    -- Fill offset array.
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_ZEROES) <= (others => '0');  -- Offset can be all zeros (no offset)
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_REG_OFFSET_x1) <= SH2PMAURegOffset sll 0;  -- or registervalue × 1
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_REG_OFFSET_x2) <= SH2PMAURegOffset sll 1;  -- registervalue × 2
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_REG_OFFSET_x4) <= SH2PMAURegOffset sll 2;  -- registervalue × 4
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_IMM_OFFSET_x1) <= SH2PMAUImmediateOffset sll 0;  -- pr ImmValue × 1
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_IMM_OFFSET_x2) <= SH2PMAUImmediateOffset sll 1;  -- ImmValue × 2
    SH2PMAUAddrOff(PMAU_OFFSET_SEL_IMM_OFFSET_x4) <= SH2PMAUImmediateOffset sll 2;  -- ImmValue × 4


    SH2PMAUInstance : MemUnit
        generic map (
            srcCnt       => pmauSourceCount, -- can come from register, GBR, or PC
            offsetCnt    => pmauOffsetCount, -- can come from R0 or instruction register
            maxIncDecBit => maxIncDecBitpmau, -- need to be able to inc/dec up to bit 3 (+- 4)
            wordsize     => regLen
        )

        port map(
            AddrSrc    => SH2PMAUAddrSrc,   
            SrcSel     => SH2PMAUSrcSel,
            AddrOff    => SH2PMAUAddrOff,
            OffsetSel  => SH2PMAUOffsetSel,
            IncDecSel  => SH2PMAUIncDecSel,
            IncDecBit  => SH2PMAUIncDecBit,
            PrePostSel => SH2PMAUPrePostSel,

            Address => genericMAUProgramAddressBus,
            AddrSrcOut => open -- PC
        );

        SH2PC <= genericMAUProgramAddressBus when (SH2PMAUReset = '1') else  (others => '0'); -- reset
        SH2ProgramAddressBus <= SH2PC; -- output of PMAU is the PC address

end  behavioral;