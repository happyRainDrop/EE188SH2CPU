----------------------------------------------------------------------------
--
--  Generic Register Array
--
--  This is an implementation of a Register Array for the register-based
--  microprocessors.  It allows the registers to be accessed as single words
--  or double words.  Multiple interfaces to the registers are allowed so they
--  may be simultaneously used as ALU registers and address registers.  Double
--  word access may be used for addressing (typically used in 8-bit
--  processors) for example.
--
--  Entities included are:
--     RegArray  - the register array
--
--  Revision History:
--     25 Jan 21  Glen George       Initial revision.
--     11 Apr 25  Glen George       Added separate address register interface.
--
--     17 May 25  Ruth Berkun       Do not initialize as undefined!
--     10 June 25 Ruth Berkun       Test combination logic for regs instead of writing on the clock
----------------------------------------------------------------------------


--
--  RegArray
--
--  This is a generic register array.  It contains regcnt wordsize bit
--  registers along with the appropriate reading and writing controls.  The
--  registers can also be read and written as double width registers.  There
--  is also two separate access ports and a write port to allow the registers
--  to be used as address registers simultaneous to their use in other blocks
--  such as the ALU.
--
--  Generics:
--    regcnt   - number of registers in the array (must be a multiple of 2)
--    wordsize - width of each register
--
--  Inputs:
--    RegIn      - input bus to the registers
--    RegInSel   - which register to write (log regcnt bits)
--    RegStore   - actually write to a register
--    RegASel    - register to read onto bus A (log regcnt bits)
--    RegBSel    - register to read onto bus B (log regcnt bits)
--    RegAxIn    - input bus for address register updates
--    RegAxInSel - which address register to write (log regcnt bits - 1)
--    RegAxStore - actually write to an address register
--    RegA1Sel   - register to read onto address bus 1 (log regcnt bits)
--    RegA2Sel   - register to read onto address bus 2 (log regcnt bits)
--    RegDIn     - input bus to the double-width registers
--    RegDInSel  - which double register to write (log regcnt bits - 1)
--    RegDStore  - actually write to a double register
--    RegDSel    - register to read onto double width bus D (log regcnt bits)
--    clock      - the system clock
--
--  Outputs:
--    RegA       - register value for bus A
--    RegB       - register value for bus B
--    RegA1      - register value for address bus 1
--    RegA2      - register value for address bus 2
--    RegD       - register value for bus D (double width bus)
--

library ieee;
use ieee.std_logic_1164.all;

entity  RegArray  is

    generic (
        regcnt   : integer := 32;    -- default number of registers is 32
        wordsize : integer := 8      -- default width is 8-bits
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

end  RegArray;

architecture behavioral of RegArray is

    type RegType is array (regcnt - 1 downto 0) of
        std_logic_vector(wordsize - 1 downto 0);

    signal Registers : RegType := (others => (others => '0'));

    alias RegDInHigh : std_logic_vector(wordsize - 1 downto 0) is
        RegDIn(2 * wordsize - 1 downto wordsize);
    alias RegDInLow  : std_logic_vector(wordsize - 1 downto 0) is
        RegDIn(wordsize - 1 downto 0);

begin

    -- Combinational write logic (priority: RegStore > RegAxStore > RegDStore)
    process (RegInSel, RegIn, RegStore,
             RegAxInSel, RegAxIn, RegAxStore,
             RegDInSel, RegDInLow, RegDInHigh, RegDStore,
             Registers)
        variable next_registers : RegType := Registers;
    begin

        -- Handle double-word write (lowest priority)
        if RegDStore = '1' then
            next_registers(2 * RegDInSel + 1) := RegDInHigh;
            next_registers(2 * RegDInSel)     := RegDInLow;
        end if;

        -- Address register write (medium priority)
        if RegAxStore = '1' then
            next_registers(RegAxInSel) := RegAxIn;
        end if;

        -- Normal register write (highest priority)
        if RegStore = '1' then
            next_registers(RegInSel) := RegIn;
        end if;

        -- Commit to internal register state
        Registers <= next_registers;
    end process;

    -- Outputs
    RegA  <= Registers(RegASel);
    RegB  <= Registers(RegBSel);
    RegA1 <= Registers(1);
    RegA2 <= Registers(2);
    RegD  <= Registers(2 * RegDSel + 1) & Registers(2 * RegDSel);

end behavioral;
