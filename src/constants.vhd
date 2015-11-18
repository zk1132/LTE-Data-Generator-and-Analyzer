library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package constants is
  constant QPSK_BITS : integer := 2;
  constant QAM16_BITS : integer := 4;
  constant QAM64_BITS : integer := 6;

  constant QPSK_IQ_MAP : IQ_map_t(0 to 2**QPSK_BITS - 1) :=
    (x"3f3504f3",
     x"bf3504f3");
  constant QAM16_IQ_MAP : IQ_map_t(0 to 2**QAM16_BITS - 1) :=
    (x"3ea1e89b",
     x"3f72dce9",
     x"bea1e89b",
     x"bf72dce9");
  constant QAM64_IQ_MAP : IQ_map_t(0 to 2**QAM64_BITS - 1) :=
    (x"3e1e01b3",
     x"3eed028c",
     x"3f45821f",
     x"3f8a417c",
     x"be1e01b3",
     x"beed028c",
     x"bf45821f",
     x"bf8a417c");

end constants;