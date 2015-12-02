library ieee;
use ieee.std_logic_1164.all;

entity clock is
  generic (period :     time      := 50 ns);
  port (clk       : out std_logic := '0');
end clock;

architecture behaviour of clock is
begin
  process
  begin
    clk <= '1', '0' after period / 2;
    wait for period;
  end process;
end behaviour;