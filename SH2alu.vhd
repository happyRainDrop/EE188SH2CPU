----------------------------------------------------------------------------
--
--  SH-2 ALU and Status Register
--
--  This is an SH-2 implementation of the ALU for simple microprocessors.
--  It does not include a multiplier, MAC, divider, or barrel shifter.
--
--  Packages included are:
--     SH2_CPU_Constants -- all constants for SH2 processor blocks
--  Entities included are:
--     SH2ALU       - the actual ALU
--
--  Revision History:
--     25 Jan 21  Glen George       Initial revision.
--     27 Jan 21  Glen George       Changed left/right shift selection to a
--                                  constant.
--     27 Jan 21  Glen George       Changed F-Block to be on B input of adder.
--     27 Jan 21  Glen George       Updated comments.
--     29 Jan 21  Glen George       Fixed a number of wordsize bugs.
--     29 Jan 21  Glen George       Fixed overflow signal in adder.
--     11 Apr 25  Glen George       Removed Status Register.
--     24 Apr 25  Ruth Berkun       Copied over from generic ALU.vhd
--     11 Jun 25  Nerissa Finnen    Added immediate functionality to Op A
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
package SH2ALUConstants is

  -- Register and word size configuration
  constant regLen       : integer := 32;   -- Each register is 32 bits
  constant regCount     : integer := 21;   -- 16 general + 5 special registers

  -- Flag bit positions (useful for flag bus indexing)
  constant FLAG_INDEX_CARRYOUT     : integer := 4;
  constant FLAG_INDEX_HALF_CARRY   : integer := 3;
  constant FLAG_INDEX_OVERFLOW     : integer := 2;
  constant FLAG_INDEX_ZERO         : integer := 1;
  constant FLAG_INDEX_SIGN         : integer := 0;

end package;

use work.SH2ALUConstants.all;
library ieee;
use ieee.std_logic_1164.all;

entity  SH2ALU  is
    port(
        SH2ALUOpA   : in      std_logic_vector(regLen - 1 downto 0);   -- first operand (hooked up to reg bus)
        SH2ALUOpB   : in      std_logic_vector(regLen - 1 downto 0);   -- second operand, option 1 (hooked up to reg bus)
        SH2ALUImmediateOperand : in     std_logic_vector(regLen - 1 downto 0); -- other possible second operand (immediate)
        SH2ALUOpAImmediate : in  std_logic_vector(regLen - 1 downto 0); --other operand for Op A
        SH2ALUUseImmediateOperand : in std_logic;                        -- 1 to use immediate 0 to used ALUOpB
        SH2ALUOpAUseImmediateOperand : in std_logic;                     -- 1 to use immediate 0 to used ALUOpA
        SH2Cin      : in      std_logic;                                 -- carry in
        SH2FCmd     : in      std_logic_vector(3 downto 0);              -- F-Block operation
        SH2CinCmd   : in      std_logic_vector(1 downto 0);              -- carry in operation
        SH2SCmd     : in      std_logic_vector(2 downto 0);              -- shift operation
        SH2ALUCmd   : in      std_logic_vector(1 downto 0);              -- ALU result select
        SH2ALUResult   : buffer  std_logic_vector(regLen - 1 downto 0);   -- ALU result
        FlagBus     : buffer  std_logic_vector(4 downto 0)             -- contains all generic ALU flags
    );

end  SH2ALU;


architecture  behavioral  of  SH2ALU  is

	component  ALU
        generic (
            wordsize : integer := 8      -- default width is 8-bits
        );
        port(
            ALUOpA   : in      std_logic_vector(regLen - 1 downto 0);   -- first operand
            ALUOpB   : in      std_logic_vector(regLen - 1 downto 0);   -- second operand
            Cin      : in      std_logic;                                 -- carry in
            FCmd     : in      std_logic_vector(3 downto 0);              -- F-Block operation
            CinCmd   : in      std_logic_vector(1 downto 0);              -- carry in operation
            SCmd     : in      std_logic_vector(2 downto 0);              -- shift operation
            ALUCmd   : in      std_logic_vector(1 downto 0);              -- ALU result select
            Result   : buffer  std_logic_vector(regLen - 1 downto 0);   -- ALU result
            Cout     : out     std_logic;                                 -- carry out
            HalfCout : out     std_logic;                                 -- half carry out
            Overflow : out     std_logic;                                 -- signed overflow
            Zero     : out     std_logic;                                 -- result is zero
            Sign     : out     std_logic                                  -- sign of result
        );
    end component;

    signal ALUOpB_input : std_logic_vector(regLen - 1 downto 0); -- second operand can either be from immediate or reg

    signal ALUOpA_input : std_logic_vector(regLen - 1 downto 0); -- first operand can be an immediate or reg

begin


    -- ALU: Prepare inputs
    ALUOpB_input <= SH2ALUOpB when SH2ALUUseImmediateOperand = '0' else SH2ALUImmediateOperand;

    ALUOpA_input <= SH2ALUOpA when SH2ALUOpAUseImmediateOperand = '0' else SH2ALUOpAImmediate;
    
    -- Hook up ALU inputs and output    
    SH2ALUInstance : ALU
        generic map (
            wordsize => regLen      -- Operands can be max length of one register
                                        -- We will pad the smaller operands to regLen bits too
        )

        port map (
            ALUOpA    => SH2ALUOpA,              -- Control unit will set operands,
            ALUOpB    => ALUOpB_input,                 -- and one of them can be from an immediate value
            Cin       => SH2Cin,              
            FCmd      => SH2FCmd,                   
            CinCmd    => SH2CinCmd,
            SCmd      => SH2SCmd,
            ALUCmd    => SH2ALUCmd,
            Result    => SH2ALUResult,  -- outputs
            Cout      => FlagBus(FLAG_INDEX_CARRYOUT),                      --                  
            HalfCout  => FlagBus(FLAG_INDEX_HALF_CARRY),
            Overflow  => FlagBus(FLAG_INDEX_OVERFLOW),
            Zero      => FlagBus(FLAG_INDEX_ZERO),
            Sign      => FlagBus(FLAG_INDEX_SIGN)                             
        );

end  behavioral;