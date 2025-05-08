----------------------------------------------------------------------------
--
--  SH2 Data Memory Access Unit
--
--  This is an implementation of a data memory access unit for SH2
--  microprocessors.  This unit generates the memory address for either load
--  and store operations. 
--
--  Packages included are:
--     SH2_CPU_Constants -- all constants for SH2 processor blocks
--  Entities included are:
--     SH2DMAU  - SH2 data memory access unit
--
--  Revision History:
--     24 Apr 25  Ruth Berkun       Copied over from mau.vhd template
--      3 May 25  Ruth Berkun       Fix shifting syntax error, added constants package
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
package SH2DMAUConstants is

  -- Register and word size configuration
  constant regLen       : integer := 32;   -- Each register is 32 bits
  constant regCount     : integer := 21;   -- 16 general + 5 special registers

  -- DMAU configuration
  constant dmauSourceCount  : integer := 2;    -- from reg array (Register, GBR, PC) or immediate
  constant dmauOffsetCount  : integer := 7;    -- 0, R0x1, R0x2, R0x4, Immx1, Immx2, Immx4
  constant maxIncDecBitDMAU     : integer := 3;    -- Allow inc/dec up to bit 3 (+-4) 

end package;

use work.SH2DMAUConstants.all;
library ieee;
use ieee.std_logic_1164.all;

entity  SH2DMAU  is
    port(
        SH2DMAURegSource :  in std_logic_vector(regLen-1 downto 0);
        SH2DMAUImmediateSource :  in std_logic_vector(regLen-1 downto 0);
        SH2DMAURegOffset :  in std_logic_vector(regLen-1 downto 0);
        SH2DMAUImmediateOffset :  in std_logic_vector(regLen-1 downto 0);
        SH2DMAUSrcSel     : in      integer  range dmauSourceCount - 1 downto 0;
        SH2DMAUOffsetSel  : in      integer  range dmauOffsetCount - 1 downto 0;
        SH2DMAUIncDecSel  : in      std_logic;
        SH2DMAUIncDecBit  : in      integer  range maxIncDecBitDMAU downto 0;
        SH2DMAUPrePostSel : in      std_logic;
        SH2DataAddressBus    : out     std_logic_vector(regLen - 1 downto 0);
        SH2DataAddressSrc : buffer  std_logic_vector(regLen - 1 downto 0)
    );

end  SH2DMAU;

library ieee;
use ieee.std_logic_1164.all;
use work.array_type_pkg.all;

architecture  behavioral  of  SH2DMAU  is

	component  MemUnit
        generic (
            srcCnt       : integer;
            offsetCnt    : integer;
            maxIncDecBit : integer := 0; -- default is only inc/dec bit 0
            wordsize     : integer := 16 -- default address width is 16 bits
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

    -- DMAU source arrays
    signal SH2DMAUAddrSrc : std_logic_array(dmauSourceCount - 1 downto 0)(regLen - 1 downto 0);
    signal SH2DMAUAddrOff :std_logic_array(dmauOffsetCount - 1 downto 0)(regLen - 1 downto 0);

begin

    -- DMAU: Prepare inputs
    -- Fill source array. 
    SH2DMAUAddrSrc(0) <= SH2DMAURegSource; --Sources can come from register array (general register, GBR, or PC)
    SH2DMAUAddrSrc(1) <= SH2DMAUImmediateSource; --or be an immediate value from the control unit
    -- Fill offset array.
    SH2DMAUAddrOff(0) <= (others => '0');  -- Offset can be all zeros (no offset)
    SH2DMAUAddrOff(1) <= SH2DMAURegOffset;  -- or registervalue × 1
    SH2DMAUAddrOff(2) <= SH2DMAURegOffset sll 1;  -- registervalue × 2
    SH2DMAUAddrOff(3) <= SH2DMAURegOffset sll 2;  -- registervalue × 4
    SH2DMAUAddrOff(4) <= SH2DMAUImmediateOffset;  -- pr ImmValue × 1
    SH2DMAUAddrOff(5) <= SH2DMAUImmediateOffset sll 1;  -- ImmValue × 2
    SH2DMAUAddrOff(6) <= SH2DMAUImmediateOffset sll 2;  -- ImmValue × 4


    SH2DMAUInstance : MemUnit
        generic map (
            srcCnt       => dmauSourceCount, -- can come from register, GBR, or PC
            offsetCnt    => dmauOffsetCount, -- can come from R0 or instruction register
            maxIncDecBit => maxIncDecBitDMAU, -- need to be able to inc/dec up to bit 3 (+- 4)
            wordsize     => regLen
        )

        port map (
            AddrSrc    => SH2DMAUAddrSrc,   
            SrcSel     => SH2DMAUSrcSel,
            AddrOff    => SH2DMAUAddrOff,
            OffsetSel  => SH2DMAUOffsetSel,
            IncDecSel  => SH2DMAUIncDecSel,
            IncDecBit  => SH2DMAUIncDecBit,
            PrePostSel => SH2DMAUPrePostSel,

            Address => SH2DataAddressBus,
            AddrSrcOut => SH2DataAddressSrc -- control unit knows which source we input;
                                            -- so if there was any pre/post increment/decrement
                                            -- it knows where to feed SH2DataAddressSrc back into 
        );

end  behavioral;