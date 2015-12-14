library ieee;
use ieee.std_logic_1164.all;
use work.constants.all;
use work.types.all;

entity lte_signal_generator is
  port (clk   : in std_logic;
        reset : in std_logic);
end entity;

architecture structural of lte_signal_generator is
  component gold_sequence_generator is
    generic (sequence_width_g : integer);
    port (clk          : in  std_logic;
          reset        : in  std_logic;
          halt         : in  std_logic;
          bit_sequence : out std_logic_vector(sequence_width_g - 1 downto 0));
  end component;

  component subcarrier_controller is
    generic (total_subcarriers  : integer;
             active_subcarriers : integer);
    port (clk             : in  std_logic;
          reset           : in  std_logic;
          halt            : in  std_logic;
          data_enable     : out std_logic;
          start_of_packet : out std_logic;
          end_of_packet   : out std_logic);
  end component;

  component iq_mapper is
    generic (sample_map_g       : iq_map_t;
             modulation_width_g : integer);
    port (bit_sequence : in  std_logic_vector(modulation_width_g - 1 downto 0);
          enable       : in  std_logic;
          i            : out std_logic_vector(31 downto 0);
          q            : out std_logic_vector(31 downto 0));
  end component;

  component digit_reverter is
    port (i          : out std_logic_vector(31 downto 0);
          q          : out std_logic_vector(31 downto 0);
          i_reverted : out std_logic_vector(31 downto 0);
          q_reverted : out std_logic_vector(31 downto 0));
  end component;

  component inverse_fft is
    port (clk          : in  std_logic                     := 'X';
          reset_n      : in  std_logic                     := 'X';
          sink_valid   : in  std_logic                     := 'X';
          sink_ready   : out std_logic;
          sink_error   : in  std_logic_vector(1 downto 0)  := (others => 'X');
          sink_sop     : in  std_logic                     := 'X';
          sink_eop     : in  std_logic                     := 'X';
          sink_real    : in  std_logic_vector(31 downto 0) := (others => 'X');
          sink_imag    : in  std_logic_vector(31 downto 0) := (others => 'X');
          fftpts_in    : in  std_logic_vector(7 downto 0)  := (others => 'X');
          source_valid : out std_logic;
          source_ready : in  std_logic                     := 'X';
          source_error : out std_logic_vector(1 downto 0);
          source_sop   : out std_logic;
          source_eop   : out std_logic;
          source_real  : out std_logic_vector(31 downto 0);
          source_imag  : out std_logic_vector(31 downto 0);
          fftpts_out   : out std_logic_vector(7 downto 0));
  end component;

  component cyclic_prefix is
    generic (input_size      : integer;
             slot_width      : integer;
             cp_short_length : integer;
             cp_long_length  : integer);
    port (clk            : in  std_logic;
          reset          : in  std_logic;
          start_of_input : in  std_logic;
          end_of_input   : in  std_logic;
          tx_controller_cp : out std_logic;
          time_i, time_q : out std_logic_vector(31 downto 0);
          time_prefixed  : out std_logic_vector(63 downto 0));
  end component;

  component tx_controller is
    port (fifo_full : in std_logic;
          halt : out std_logic;
          start_of_packet_i : in std_logic;
          end_of_packet_i : in std_logic;
          start_of_packet_o : out std_logic;
          end_of_packet_o : out std_logic;
          transmit  : out std_logic);
  end component;

  component tx_fifo is
    port (data    : in  std_logic_vector(63 downto 0);
          clock   : in  std_logic;
          rdreq   : in  std_logic;
          wrreq   : in  std_logic;
          q       : out std_logic_vector(63 downto 0);
          rdempty : out std_logic;
          wrfull  : out std_logic);
  end component;

  component noisifier is
    port (clk    : in  std_logic;
          reset  : in  std_logic;
          enable : in  std_logic;
          i_in   : in  std_logic_vector(31 downto 0);
          q_in   : in  std_logic_vector(31 downto 0);
          i_out  : out std_logic_vector(31 downto 0);
          q_out  : out std_logic_vector(31 downto 0));
  end component;

  constant SEQUENCE_WIDTH : integer := QAM64_BITS;

  signal i, i_noise, q, q_noise : std_logic_vector(31 downto 0);

  signal buffer_enable : std_logic;

  signal bit_sequence, buffered_bit_sequence :
    std_logic_vector(SEQUENCE_WIDTH - 1 downto 0);

  signal iq_prefixed : std_logic_vector(63 downto 0);

  signal time_cp : std_logic_vector(63 downto 0);

  signal freq_i, freq_q : std_logic_vector(31 downto 0);
  signal time_i, time_q : std_logic_vector(31 downto 0);

  signal subcarrier_controller_enable : std_logic;

  signal tx_controller_in_sop, tx_controller_in_eop,
    tx_controller_out_sop, tx_controller_out_eop : std_logic;

  signal tx_controller_halt : std_logic;

  signal tx_controller_fifo_write, tx_controller_read_request : std_logic;

  signal v_t : std_logic_vector(63 downto 0);

  signal v_i, v_q : std_logic_vector(31 downto 0);

  signal fifo_full : std_logic;

begin

  v_i <= v_t(31 downto 0);
  v_q <= v_t(63 downto 32);

  i_prbs_0 : gold_sequence_generator
    generic map (sequence_width_g => SEQUENCE_WIDTH)
    port map (clk          => clk,
              reset        => reset,
              halt         => tx_controller_halt,
              bit_sequence => bit_sequence);

  i_subcarrier_controller_0 : subcarrier_controller
    generic map (total_subcarriers  => FFT_SIZE,
                 active_subcarriers => ACTIVE_SUBCARRIERS)
    port map (clk             => clk,
              reset           => reset,
              halt            => tx_controller_halt,
              data_enable     => subcarrier_controller_enable,
              start_of_packet => tx_controller_in_sop,
              end_of_packet   => tx_controller_in_eop);

  i_iq_mapper_qam64 : iq_mapper
    generic map (sample_map_g       => QAM64_IQ_MAP,
                 modulation_width_g => SEQUENCE_WIDTH)
    port map (bit_sequence => buffered_bit_sequence,
              enable       => subcarrier_controller_enable,
              i            => i,
              q            => q);

  i_digit_reverter_0 : digit_reverter
    port map (i          => i,
              q          => q,
              i_reverted => freq_i,
              q_reverted => freq_q);

  i_inverse_fft_0 : inverse_fft
    port map (clk          => clk,
              reset_n      => reset,
              sink_valid   => open,     --tx_controller_out_valid,
              sink_ready   => open,     --tx_controller_out_ready,
              sink_error   => open,     --tx_controller_out_error,
              sink_sop     => tx_controller_out_sop,
              sink_eop     => tx_controller_out_eop,
              sink_real    => freq_i,
              sink_imag    => freq_q,
              fftpts_in    => open,
              source_valid => open,     --tx_controller_valid,
              source_ready => open,     --tx_controller_ready,
              source_error => open,     --tx_controller_error,
              source_sop   => tx_controller_in_sop,
              source_eop   => tx_controller_in_eop,
              source_real  => time_i,
              source_imag  => time_q,
              fftpts_out   => open);

  i_cyclic_prefix_0 : cyclic_prefix
    generic map (input_size      => FFT_SIZE,
                 slot_width      => SLOT_WIDTH,
                 cp_short_length => (FFT_SIZE / 128) * 10 - (FFT_SIZE / 128),
                 cp_long_length  => (FFT_SIZE / 128) * 10)
    port map (clk            => clk,
              reset          => reset,
              start_of_input => tx_controller_in_sop,
              end_of_input   => tx_controller_in_eop,
              tx_controller_cp => tx_controller_fifo_write,
              time_i         => time_i, time_q => time_q,
              time_prefixed  => time_cp);

  i_cp_fifo_0 : tx_fifo
    port map (data    => time_cp,
              clock   => clk,           -- 1.4MHZ <- fisk
              rdreq   => tx_controller_read_request,
              wrreq   => tx_controller_fifo_write,
              q       => v_t,
              rdempty => open,
              wrfull  => fifo_full);

  i_tx_controller_0 : tx_controller
    port map (fifo_full       => fifo_full,
              halt            => tx_controller_halt,
              start_of_packet_i => tx_controller_in_sop,
              end_of_packet_i   => tx_controller_in_eop,
              start_of_packet_o => tx_controller_out_sop,
              end_of_packet_o   => tx_controller_out_eop,
              transmit   => tx_controller_read_request);

  -- Should be mapped to output of iFFT
  i_noise_0 : noisifier
    port map (clk    => clk,            -- HERPDERP
              reset  => reset,
              enable => buffer_enable,
              i_in   => v_i,
              q_in   => v_q,
              i_out  => i_noise,
              q_out  => q_noise);

end architecture;
