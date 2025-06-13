----------------------------------------------------------------------------
--
--  SH2 Register Array
--
--  This is an implementation of a Register Array for the SH-2 register-based
--  microprocessor.  It allows the registers to be accessed as single words.  
--  Multiple interfaces to the registers are allowed so they
--  may be simultaneously used as ALU registers and address registers.
--
--  Packages included are:
--     SH2_CPU_Constants -- all constants for SH2 processor blocks
--  Entities included are:
--     SH2RegArray  - the register array
--
--  Revision History:
--     25 Jan 21  Glen George       Initial revision.
--     11 Apr 25  Glen George       Added separate address register interface.
--     22 Apr 25  Ruth Berkun       Copied over for SH2Reg
--      3 May 25  Ruth Berkun       Fix syntax errors, hook up 0s to unused reg.vhd ports
--     12 May 25  Ruth Berkun       Remove PC, GBR, VBR from reg array
--     09 June 25 Ruth Berkun       Unclock registers for instantaneous access
--     13 June 25 Ruth Berkun       Add GBR, VBRback into reg array
----------------------------------------------------------------------------

--
--  Package containing the constants for the Memory Unit
--

library ieee;
use ieee.std_logic_1164.all;

package SH2RegConstants is

  -- Register and word size configuration
  constant regLen       : integer := 32;   -- Each register is 32 bits
  constant regCount     : integer := 20;   -- 16 general + 4 special registers (PR, SR, GBR, VBR)

end package;

use work.SH2RegConstants.all;
library ieee;
use ieee.std_logic_1164.all;

entity  SH2RegArray  is
    port(
        SH2RegIn      : in   std_logic_vector(regLen - 1 downto 0);
        SH2RegInSel   : in   integer  range regCount - 1 downto 0;
        SH2RegStore   : in   std_logic;
        SH2RegASel    : in   integer  range regCount - 1 downto 0;
        SH2RegBSel    : in   integer  range regCount - 1 downto 0;
        SH2RegAxIn    : in   std_logic_vector(regLen - 1 downto 0);
        SH2RegAxInSel : in   integer  range regCount - 1 downto 0;
        SH2RegAxStore : in   std_logic;
        SH2RegA1Sel   : in   integer  range regCount - 1 downto 0;
        SH2RegA2Sel   : in   integer  range regCount - 1 downto 0;
        SH2clock      : in   std_logic;
        SH2RegA       : out  std_logic_vector(regLen - 1 downto 0);
        SH2RegB       : out  std_logic_vector(regLen - 1 downto 0);
        SH2RegA1      : out  std_logic_vector(regLen - 1 downto 0);
        SH2RegA2      : out  std_logic_vector(regLen - 1 downto 0)
    );

end  SH2RegArray;


architecture  behavioral  of  SH2RegArray  is

	component  RegArray
        generic (
            regcnt   : integer := regCount;    -- default number of registers is 18: 16 general registers, 
            -- 2 more registers for PR, SR
            wordsize : integer := regLen     -- default width is 32-bits (each register is 32 bits long)
        );

        port(
            RegIn      : in   std_logic_vector(wordsize - 1 downto 0);
            RegInSel   : in   integer  range regcnt - 1 downto 0;
            RegStore   : in   std_logic;
            RegASel    : in   integer  range regcnt - 1 downto 0;
            RegBSel    : in   integer  range regcnt - 1 downto 0;
            RegAxIn    : in   std_logic_vector(wordsize - 1 downto 0);
            RegAxInSel : in   integer  range regcnt - 1 downto 0;
            RegAxStore : in   std_logic;
            RegA1Sel   : in   integer  range regcnt - 1 downto 0;
            RegA2Sel   : in   integer  range regcnt - 1 downto 0;
            RegDIn     : in   std_logic_vector(2 * wordsize - 1 downto 0);
            RegDInSel  : in   integer  range regcnt/2 - 1 downto 0;
            RegDStore  : in   std_logic;
            RegDSel    : in   integer  range regcnt/2 - 1 downto 0;
            clock      : in   std_logic;
            RegA       : out  std_logic_vector(wordsize - 1 downto 0);
            RegB       : out  std_logic_vector(wordsize - 1 downto 0);
            RegA1      : out  std_logic_vector(wordsize - 1 downto 0);
            RegA2      : out  std_logic_vector(wordsize - 1 downto 0);
            RegD       : out  std_logic_vector(2 * wordsize - 1 downto 0)
        );
    end component;


begin

    SH2RegArrayInstance : RegArray
        generic map (
            regcnt   => regCount,    -- 16 general, 5 specialized
            wordsize => regLen      -- 32 bits per register
        )

        port map (
            RegIn      => SH2RegIn,
            RegInSel   => SH2RegInSel,
            RegStore   => SH2RegStore,
            RegASel    => SH2RegASel,
            RegBSel    => SH2RegBSel,
            RegAxIn    => SH2RegAxIn,
            RegAxInSel => SH2RegAxInSel,
            RegAxStore => SH2RegAxStore,
            RegA1Sel   => SH2RegA1Sel,
            RegA2Sel   => SH2RegA2Sel,
            RegDIn     => (others => '0'),
            RegDInSel  => 0,
            RegDStore  => '0',
            RegDSel    => 0,
            clock      => SH2clock,
            RegA       => SH2RegA,
            RegB       => SH2RegB,
            RegA1      => SH2RegA1,
            RegA2      => SH2RegA2,
            RegD       => open
        );

end  behavioral;