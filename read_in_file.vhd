library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_textio.all;
use ieee.numeric_std.all;
use std.textio.all;

-- Code block to load SH-2 machine code into RAM block 0
-- Assumes machine code is stored as 32-bit hexadecimal values (one per line)
-- and loads them starting at START_ADDR0.
-- This uses a for loop instead of a procedure for easier debugging.

-- Signals assumed to be declared elsewhere:
-- RAMbits0 : inout RAMtype;
-- SH2AddressBus : out std_logic_vector(31 downto 0);
-- SH2DataBus : out std_logic_vector(31 downto 0);
-- WE0, WE1, WE2, WE3 : out std_logic;
-- START_ADDR0 : integer constant;
-- MEMSIZE : integer constant;

process
    file infile : text;
    variable linebuf : line;
    variable hexval : std_logic_vector(31 downto 0);
    variable addr : integer := 0;
begin
    -- Open the input file
    file_open(infile, "program.mem", READ_MODE);

    while not endfile(infile) loop
        readline(infile, linebuf);
        read(linebuf, hexval);

        if addr >= MEMSIZE then
            report "Error: Program exceeds RAM block 0 size." severity error;
            exit;
        end if;

        -- Drive the address and data
        SH2AddressBus <= std_logic_vector(to_unsigned(START_ADDR0 + addr, 32));
        SH2DataBus <= hexval;

        -- Enable all bytes for write (active low)
        WE0 <= '0';
        WE1 <= '0';
        WE2 <= '0';
        WE3 <= '0';

        -- Simulate a write event (normally this would be clocked)
        wait for 10 ns;

        -- Disable write (set back to inactive)
        WE0 <= '1';
        WE1 <= '1';
        WE2 <= '1';
        WE3 <= '1';

        addr := addr + 1;
    end loop;

    -- Close the file after reading
    file_close(infile);

    wait;
end process;
