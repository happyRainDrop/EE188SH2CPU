library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity CPU_Testbench is
end CPU_Testbench;

architecture behavior of CPU_Testbench is

    constant memBlockWordSize : integer := 8;
    constant regLen : integer := 32;

    component CPUtoplevel
        port(
            Reset          : in  std_logic;
            NMI            : in  std_logic;
            INT            : in  std_logic;
            RE0, RE1, RE2, RE3 : out std_logic;
            WE0, WE1, WE2, WE3 : out std_logic;
            SH2clock       : in  std_logic;
            SH2DataBus     : buffer std_logic_vector(regLen - 1 downto 0);
            SH2AddressBus  : inout std_logic_vector(regLen - 1 downto 0)
        );
    end component;

    -- DUT signals
    signal Reset          : std_logic := '1';
    signal NMI            : std_logic := '0';
    signal INT            : std_logic := '0';
    signal RE0, RE1, RE2, RE3 : std_logic;
    signal WE0, WE1, WE2, WE3 : std_logic;
    signal SH2clock       : std_logic := '0';
    signal SH2DataBus     : std_logic_vector(regLen - 1 downto 0);
    signal SH2AddressBus  : std_logic_vector(regLen - 1 downto 0);

    -- Internal memory access (assumes internal memory is accessible)
    signal RAMbits0, RAMbits1, RAMbits2, RAMbits3 : std_logic_vector(31 downto 0);

    -- For output
    file mem_dump : text open write_mode is "cpu_mem_output.txt";

begin

    -- Clock process
    clk_proc: process
    begin
        SH2clock <= '0';
        wait for 5 ns;
        SH2clock <= '1';
        wait for 5 ns;
    end process;

    -- Instantiate CPU
    DUT: CPUtoplevel
        port map (
            Reset          => Reset,
            NMI            => NMI,
            INT            => INT,
            RE0            => RE0,
            RE1            => RE1,
            RE2            => RE2,
            RE3            => RE3,
            WE0            => WE0,
            WE1            => WE1,
            WE2            => WE2,
            WE3            => WE3,
            SH2clock       => SH2clock,
            SH2DataBus     => SH2DataBus,
            SH2AddressBus  => SH2AddressBus
        );

    -- Test sequence
    stimulus: process
        variable L : line;
    begin

        ------------------------------------------------------------------- START
        -- Reset (active low)
        Reset <= '0';
        wait for 20 ns;
        Reset <= '1';

        -- Start with: read off
        RE0 <= '1';
        RE1 <= '1';
        RE2 <= '1';
        RE3 <= '1';

        -- Start with: write off
        RE0 <= '1';
        RE1 <= '1';
        RE2 <= '1';
        RE3 <= '1';

        -------------------------------------------------------------------- WRITING

        for i in 0 to 3 loop        -- Loop over memory blocks

            for j in 0 to memBlockWordSize-1 loop   -- Looping over addresses in memory blocks

                -- Read bytes individually
                wait until falling_edge(SH2clock);
                SH2AddressBus <= std_logic_vector(to_unsigned(i * memBlockWordSize + j, 32)); 
                SH2DataBus <= std_logic_vector(to_unsigned(i * memBlockWordSize + j, 32)); 
                WE0 <= '0'; WE1 <= '0'; WE2 <= '0'; WE3 <= '0'; 

                wait until rising_edge(SH2clock);
                SH2DataBus <= (others => 'Z');
                WE0 <= '1'; WE1 <= '1'; WE2 <= '1'; WE3 <= '1';
            end loop;
        end loop;

        -------------------------------------------------------------------- READING

        -- Read all memory contents
        write(L, string'("Memory Dump by Block (32 words each):")); 
        writeline(mem_dump, L);

        for i in 0 to 3 loop        -- Loop over memory blocks

            write(L, string'("===============================")); 
            writeline(mem_dump, L);

            for j in 0 to memBlockWordSize-1 loop   -- Looping over addresses in memory blocks

                wait until falling_edge(SH2clock);
                SH2AddressBus <= std_logic_vector(to_unsigned(i * memBlockWordSize + j, 32)); 
                RE0 <= '0'; RE1 <= '0'; RE2 <= '0'; RE3 <= '0'; 

                wait until rising_edge(SH2clock);
                RE0 <= '1'; RE1 <= '1'; RE2 <= '1'; RE3 <= '1';

                write(L, string'("Addr "));
                write(L, i);
                write(L, string'(", "));
                write(L, j);
                write(L, string'(" at "));
                write(L, SH2AddressBus);
                write(L, string'(" index "));
                write(L, i * memBlockWordSize + j, right, 3);
                write(L, string'(": "));
                write(L, SH2DataBus);
                writeline(mem_dump, L);

            end loop;
        end loop;

        file_close(mem_dump);

        stop;

    end process;

end behavior;
