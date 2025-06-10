----------------------------------------------------------------------------
--
--  CPU_Testbench.vhd
--
--  Simulates 
--
--  Entities instantiated:
--      - CPUtoplevel
--
--  Revision History:
--      07 May 25  Ruth Berkun      Test writing one number to a single address in RAM
--      09 May 25  Ruth Berkun      Test all of memory is filled completed (with each of the 4 blocks having 8 32-bit words)
--      12 May 25  Ruth Berkun      Modify reading portion to come from text file
--      12 May 25  Ruth Berkun      Add Enable signal
--      13 May 25  Ruth Berkun      Remove Enable signal, put memory instantiation here
--      14 May 25  Ruth Berkun      Resolved clocking issues between switching from testbench to CPU-driven memory mode
--      17 May 25  Ruth Berkun      Change so that each instruction takes one full slot (low byte of 32 bits) in memory
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity CPU_Testbench is
end CPU_Testbench;

architecture behavior of CPU_Testbench is

    constant memBlockWordSize : integer := 25;
    constant regLen : integer := 32;
    constant instrLen : integer := 16;
    constant zeroes16 : std_logic_vector(15 downto 0) := (others => '0');

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
    signal memRE0, memRE1, memRE2, memRE3 : std_logic;
    signal memWE0, memWE1, memWE2, memWE3 : std_logic;
    signal SH2clock       : std_logic := '0';
    signal SH2DataBus     : std_logic_vector(regLen - 1 downto 0);
    signal SH2AddressBus  : std_logic_vector(regLen - 1 downto 0);

    -- Interfacing to memory unit
    signal cpuRE0, cpuRE1, cpuRE2, cpuRE3 : std_logic;
    signal cpuWE0, cpuWE1, cpuWE2, cpuWE3 : std_logic;
    signal tbRE0, tbRE1, tbRE2, tbRE3 : std_logic;
    signal tbWE0, tbWE1, tbWE2, tbWE3 : std_logic;

    -- For input and output
    file infile : text open read_mode is "cpu_test_program.txt";
    file mem_dump : text open write_mode is "cpu_mem_output.txt";

begin

    -- Instantiate memory
    SH2ExternalMemory : entity work.MEMORY32x32
    generic map (
        MEMSIZE     => memBlockWordSize,
        START_ADDR0 => (0 * memBlockWordSize),
        START_ADDR1 => (1 * memBlockWordSize),
        START_ADDR2 => (2 * memBlockWordSize),
        START_ADDR3 => (3 * memBlockWordSize)
    )
    port map (
        RE0    => memRE0,
        RE1    => memRE1,
        RE2    => memRE2,
        RE3    => memRE3, 
        WE0    => memWE0, 
        WE1    => memWE1, 
        WE2    => memWE2, 
        WE3    => memWE3, 
        MemAB  => SH2AddressBus, 
        MemDB  => SH2DataBus 
    );

    -- Memory control multiplexing
    memRE0 <= tbRE0 when Reset = '0' else cpuRE0;
    memRE1 <= tbRE1 when Reset = '0' else cpuRE1;
    memRE2 <= tbRE2 when Reset = '0' else cpuRE2;
    memRE3 <= tbRE3 when Reset = '0' else cpuRE3;

    memWE0 <= tbWE0 when Reset = '0' else cpuWE0;
    memWE1 <= tbWE1 when Reset = '0' else cpuWE1;
    memWE2 <= tbWE2 when Reset = '0' else cpuWE2;
    memWE3 <= tbWE3 when Reset = '0' else cpuWE3;

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
            RE0            => cpuRE0,
            RE1            => cpuRE1,
            RE2            => cpuRE2,
            RE3            => cpuRE3,
            WE0            => cpuWE0,
            WE1            => cpuWE1,
            WE2            => cpuWE2,
            WE3            => cpuWE3,
            SH2clock       => SH2clock,
            SH2DataBus     => SH2DataBus,
            SH2AddressBus  => SH2AddressBus
        );

    -- Test sequence
    stimulus: process
        variable L : line;
        variable addr : integer := 0;
        variable opcode : std_logic_vector(instrLen-1 downto 0);
    begin

        ------------------------------------------------------------------- INIT

        -- Reset (active low): Reset so that CPU cannot touch memory
        Reset <= '0';

        -- Start with: read off
        tbRE0 <= '1';
        tbRE1 <= '1';
        tbRE2 <= '1';
        tbRE3 <= '1';

        -- Start with: write off
        tbWE0 <= '1';
        tbWE1 <= '1';
        tbWE2 <= '1';
        tbWE3 <= '1';

        -------------------------------------------------------------------- WRITING

        -- Code block to load SH-2 machine code into RAM block 0
        -- Assumes machine code is stored as 16-bit hexadecimal values (one per line)
        -- and loads them starting at START_ADDR0.


        while not endfile(infile) loop
            readline(infile, L);
            read(L, opcode);

            -- Write bytes individually
            wait until falling_edge(SH2clock);
            SH2AddressBus <= std_logic_vector(to_unsigned(addr, 32)); 
            SH2DataBus <= zeroes16 & opcode; 
            tbWE0 <= '0'; tbWE1 <= '0'; tbWE2 <= '1'; tbWE3 <= '1'; 

            -- written low byte so next instruction need to write high byte of new memory location
            addr := addr + 1;

            -- Done writing, set writing idle
            wait until rising_edge(SH2clock);
            tbWE0 <= '1'; tbWE1 <= '1'; tbWE2 <= '1'; tbWE3 <= '1';
            -- report "addr = " & to_hstring(SH2AddressBus);
            -- report "val = " & to_hstring(SH2DataBus);

        end loop;

        file_close(infile);
        wait until falling_edge(SH2clock);     -- follow pattern of waiting until falling edge of clock to change address bus
        SH2DataBus <= (others => 'Z');         -- let CPU control data and address bus now
        SH2AddressBus <= (others => 'Z');       

        -------------------------------------------------------------------- TURN ON CPU AND THE OFF
        report "Ready for CPU to access memory.";
        wait until rising_edge(SH2clock);     -- reset on the rising edge
        Reset <= '1';
        wait for 250 ns;
        wait until rising_edge(SH2clock);     -- reset on the rising edge
        Reset <= '0';

        wait until falling_edge(SH2clock);     -- follow pattern of waiting until falling edge of clock to change address bus
        SH2DataBus <= (others => 'Z');         -- let CPU control data and address bus now
        SH2AddressBus <= (others => 'Z'); 
        report "CPU DONE!!";
        
        wait until falling_edge(SH2clock);     -- wait 1 more clock for CPU to recognize it's in the "zero clock" state

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
                tbRE0 <= '0'; tbRE1 <= '0'; tbRE2 <= '0'; tbRE3 <= '0'; 

                wait until rising_edge(SH2clock);
                tbRE0 <= '1'; tbRE1 <= '1'; tbRE2 <= '1'; tbRE3 <= '1';
                -- report "addr = " & to_hstring(SH2AddressBus);
                -- report "val = " & to_hstring(SH2DataBus);

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