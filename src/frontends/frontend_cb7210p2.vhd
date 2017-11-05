-- frontend with cb7210.2 style register layout
-- It has been extended with the addition or a isr0/imr0 register at page 1, offset 6.
-- Author: Frank Mori Hess fmh6jj@gmail.com
-- Copyright 2017 Frank Mori Hess
--

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.interface_function_common.all;
use work.integrated_interface_functions.all;

entity frontend_cb7210p2 is
	generic(num_address_lines : integer := 3;
		clock_frequency_KHz : integer := 20000);
	-- read, write_inverted, chip_select_inverted, address, and host_data_bus_in are assumed
	-- to by synched to clock
	port(
		clock : in std_logic;
		chip_select_inverted : in std_logic;
		dma_ack_inverted : in std_logic;
		read_inverted : in std_logic;
		reset : in std_logic;
		address : in std_logic_vector(num_address_lines - 1 downto 0); 
		write_inverted : in std_logic;
		host_data_bus_in : in std_logic_vector(7 downto 0);
		gpib_ATN_inverted_in : in std_logic; 
		gpib_DAV_inverted_in : in std_logic; 
		gpib_EOI_inverted_in : in std_logic; 
		gpib_IFC_inverted_in : in std_logic; 
		gpib_NDAC_inverted_in : in std_logic; 
		gpib_NRFD_inverted_in : in std_logic; 
		gpib_REN_inverted_in : in std_logic; 
		gpib_SRQ_inverted_in : in std_logic; 
		gpib_DIO_inverted_in : in std_logic_vector(7 downto 0);

		tr1 : out std_logic;
		tr2 : out std_logic;
		tr3 : out std_logic;
		interrupt : out std_logic;

		dma_request : out std_logic;
		host_data_bus_out : out std_logic_vector(7 downto 0);
		gpib_ATN_inverted_out : out std_logic; 
		gpib_DAV_inverted_out : out std_logic; 
		gpib_EOI_inverted_out : out std_logic; 
		gpib_IFC_inverted_out : out std_logic; 
		gpib_NDAC_inverted_out : out std_logic; 
		gpib_NRFD_inverted_out : out std_logic; 
		gpib_REN_inverted_out : out std_logic; 
		gpib_SRQ_inverted_out : out std_logic; 
		gpib_DIO_inverted_out : out std_logic_vector(7 downto 0);

		--rather than relying on the driver to properly configure the modes
		-- of the tr2 and tr3 outputs, these outputs can be used instead
		EOI_output_enable : out std_logic;
		not_controller_in_charge : out std_logic; -- transceiver DC
		pullup_disable : out std_logic; -- transceiver PE
		talk_enable : out std_logic; -- transceiver TE
		trigger : out std_logic 
	);
end frontend_cb7210p2;
     
architecture frontend_cb7210p2_arch of frontend_cb7210p2 is
	signal bus_ATN_inverted_in : std_logic; 
	signal bus_DAV_inverted_in :  std_logic; 
	signal bus_EOI_inverted_in :  std_logic; 
	signal bus_IFC_inverted_in :  std_logic; 
	signal bus_NDAC_inverted_in :  std_logic; 
	signal bus_NRFD_inverted_in :  std_logic; 
	signal bus_REN_inverted_in :  std_logic; 
	signal bus_SRQ_inverted_in :  std_logic; 
	signal bus_DIO_inverted_in :  std_logic_vector(7 downto 0);

	signal configured_eos_character : std_logic_vector(7 downto 0);
	signal ignore_eos_bit_7 : std_logic;
	signal configured_primary_address : std_logic_vector(4 downto 0);
	signal configured_secondary_address :std_logic_vector(4 downto 0);
	signal local_parallel_poll_config : std_logic;
	signal local_parallel_poll_sense : std_logic;
	signal local_parallel_poll_response_line : std_logic_vector(2 downto 0);
	signal check_for_listeners : std_logic;
	signal no_listeners : std_logic;
	signal first_T1_terminal_count : std_logic_vector(15 downto 0);
	signal T1_terminal_count : std_logic_vector(15 downto 0);
	signal gpib_to_host_byte : std_logic_vector(7 downto 0);
	signal gpib_to_host_byte_read : std_logic;
	signal gpib_to_host_byte_end : std_logic;
	signal gpib_to_host_byte_eos : std_logic;
	signal host_to_gpib_data_byte : std_logic_vector(7 downto 0);
	signal host_to_gpib_data_byte_end : std_logic;
	signal host_to_gpib_data_byte_write : std_logic;
	signal host_to_gpib_data_byte_latched : std_logic;
	signal controller_state_p1 : C_state_p1;
	signal device_clear_state : DC_state;
	signal device_trigger_state : DT_state;
	signal parallel_poll_state_p1 : PP_state_p1;
	signal talker_state_p1 : TE_state_p1;
	
	signal ist : std_logic;
	signal lon : std_logic;	
	signal lpe : std_logic;
	signal lun : std_logic;
	signal ltn : std_logic;
	signal pon : std_logic;
	signal rdy : std_logic;
	signal rsv : std_logic;
	signal rtl : std_logic;
	signal ton : std_logic;
	signal tcs : std_logic;
	signal local_STB : std_logic_vector(7 downto 0);
	
	signal safe_reset : std_logic;
	signal latched_host_data_byte_in : std_logic_vector(7 downto 0);
	signal latched_address : std_logic_vector(num_address_lines - 1 downto 0);
	signal host_write_selected : std_logic;
	signal host_read_selected : std_logic;
	signal register_page : std_logic_vector(3 downto 0);
	signal host_data_bus_out_buffer : std_logic_vector(7 downto 0);
	
	signal transmit_receive_mode : std_logic_vector(1 downto 0);
	signal address_mode : std_logic_vector(1 downto 0);
	signal gpib_address_0 : std_logic_vector(4 downto 0);
	signal enable_talker_gpib_address_0 : std_logic;
	signal enable_listener_gpib_address_0 : std_logic;
	signal gpib_address_1 : std_logic_vector(4 downto 0);
	signal enable_talker_gpib_address_1 : std_logic;
	signal enable_listener_gpib_address_1 : std_logic;
	signal enable_address_register_1 : std_logic;
	signal ultra_fast_T1_delay : std_logic;
	signal high_speed_T1_delay : std_logic;
	signal pon_pulse : std_logic;
	
	signal talk_enable_buffer : std_logic;
	signal not_controller_in_charge_buffer : std_logic;
	signal pullup_disable_buffer : std_logic;
	signal EOI_output_enable_buffer : std_logic;
	signal trigger_buffer : std_logic;

	-- overhead is fixed number of clock ticks of overhead even when using a timing delay of zero
	function to_clock_ticks (nanoseconds : in integer; overhead : in integer) return std_logic_vector is
		constant nanos_per_milli : integer := 1000000;
		variable ticks : integer;
	begin
		ticks := (nanoseconds * clock_frequency_KHz + nanos_per_milli - 1) / nanos_per_milli - overhead;
		if ticks < 0 then
			ticks := 0;
		end if;
		return std_logic_vector(to_unsigned(ticks, T1_terminal_count'LENGTH));
	end to_clock_ticks;
	constant T1_clock_ticks_2us : std_logic_vector(T1_terminal_count'RANGE) := to_clock_ticks(2000, 2);
	constant T1_clock_ticks_1100ns : std_logic_vector(T1_terminal_count'RANGE) := to_clock_ticks(1100, 2);
	constant T1_clock_ticks_500ns : std_logic_vector(T1_terminal_count'RANGE) := to_clock_ticks(500, 2);
	constant T1_clock_ticks_350ns : std_logic_vector(T1_terminal_count'RANGE) := to_clock_ticks(350, 2);
	
	begin
	my_integrated_interface_functions: entity work.integrated_interface_functions 
		port map (
			clock => clock,
			bus_DIO_inverted_in => bus_DIO_inverted_in,
			bus_REN_inverted_in => bus_REN_inverted_in,
			bus_IFC_inverted_in => bus_IFC_inverted_in,
			bus_SRQ_inverted_in => bus_SRQ_inverted_in,
			bus_EOI_inverted_in => bus_EOI_inverted_in,
			bus_ATN_inverted_in => bus_ATN_inverted_in,
			bus_NDAC_inverted_in => bus_NDAC_inverted_in,
			bus_NRFD_inverted_in => bus_NRFD_inverted_in,
			bus_DAV_inverted_in => bus_DAV_inverted_in,
			bus_DIO_inverted_out => gpib_DIO_inverted_out,
			bus_REN_inverted_out => gpib_REN_inverted_out,
			bus_IFC_inverted_out => gpib_IFC_inverted_out,
			bus_SRQ_inverted_out => gpib_SRQ_inverted_out,
			bus_EOI_inverted_out => gpib_EOI_inverted_out,
			bus_ATN_inverted_out => gpib_ATN_inverted_out,
			bus_NDAC_inverted_out => gpib_NDAC_inverted_out,
			bus_NRFD_inverted_out => gpib_NRFD_inverted_out,
			bus_DAV_inverted_out => gpib_DAV_inverted_out,
			ist => ist,
			lon => lon,
			lpe => lpe,
			lun => lun,
			ltn => ltn,
			pon => pon,
			rsv => rsv,
			rtl => rtl,
			tcs => tcs,
			ton => ton,
			configured_eos_character => configured_eos_character,
			ignore_eos_bit_7 => ignore_eos_bit_7,
			configured_primary_address => configured_primary_address,
			configured_secondary_address => configured_secondary_address,
			local_parallel_poll_config => local_parallel_poll_config,
			local_parallel_poll_sense => local_parallel_poll_sense,
			local_parallel_poll_response_line => local_parallel_poll_response_line,
			check_for_listeners => check_for_listeners,
			gpib_to_host_byte_read => gpib_to_host_byte_read,
			first_T1_terminal_count => first_T1_terminal_count,
			T1_terminal_count => T1_terminal_count,
			no_listeners => no_listeners,
			gpib_to_host_byte => gpib_to_host_byte,
			gpib_to_host_byte_end => gpib_to_host_byte_end,
			gpib_to_host_byte_eos => gpib_to_host_byte_eos,
			rdy => rdy,
			host_to_gpib_data_byte => host_to_gpib_data_byte,
			host_to_gpib_data_byte_end => host_to_gpib_data_byte_end,
			host_to_gpib_data_byte_write => host_to_gpib_data_byte_write,
			host_to_gpib_data_byte_latched => host_to_gpib_data_byte_latched,
			controller_state_p1 => controller_state_p1,
			device_clear_state => device_clear_state,
			device_trigger_state => device_trigger_state,
			parallel_poll_state_p1 => parallel_poll_state_p1,
			talker_state_p1 => talker_state_p1,
			local_STB => local_STB
		);

	-- latch external gpib signals on falling clock edge
	process (clock)
	begin
		if falling_edge(clock) then
			bus_ATN_inverted_in <= gpib_ATN_inverted_in;
			bus_DAV_inverted_in <= gpib_DAV_inverted_in;
			bus_EOI_inverted_in <= gpib_EOI_inverted_in;
			bus_IFC_inverted_in <= gpib_IFC_inverted_in;
			bus_NDAC_inverted_in <= gpib_NDAC_inverted_in;
			bus_NRFD_inverted_in <= gpib_NRFD_inverted_in;
			bus_REN_inverted_in <= gpib_REN_inverted_in;
			bus_SRQ_inverted_in <= gpib_SRQ_inverted_in;
			bus_DIO_inverted_in <= gpib_DIO_inverted_in;
		end if;
	end process;
	
	-- generate reset which is asserted async but de-asserted synchronously on 
	-- falling clock edge, to avoid any potential metastability problems caused
	-- by pon deasserting near rising clock edge.
	process (reset, pon, clock)
	begin
		if to_bit(reset) = '1' or pon_pulse = '1' then
			pon <= '1';
			if to_bit(reset) = '1' then
				safe_reset <= '1';
			end if;
		elsif falling_edge(clock) then
			if to_bit(reset) = '0' then
				safe_reset <= '0';
				if pon_pulse = '0' then
					pon <= '0';
				end if;
			end if;
		end if;
	end process;
	
	host_write_selected <= not write_inverted and not chip_select_inverted;
	host_read_selected <= not read_inverted and not chip_select_inverted;
	host_data_bus_out <= host_data_bus_out_buffer when to_X01(read_inverted) = '0' else (others => 'Z');
	
	-- accept reads and writes from host
	process (safe_reset, pon, clock)
		variable prev_host_write_selected : std_logic;
		variable do_pulse_host_to_gpib_data_byte_write : boolean;
		variable prev_host_read_selected : std_logic;
		variable do_pulse_gpib_to_host_byte_read : boolean;
		variable send_eoi : std_logic;
		
		function flat_address (page : in std_logic_vector(3 downto 0);
			raw_address : in std_logic_vector(num_address_lines - 1 downto 0)) 
			return integer is
			variable page_integer : integer range 0 to 15;
			variable raw_address_integer : integer range 0 to 127;
			variable flat_address_integer : integer range 0 to 127;
		begin
			raw_address_integer := to_integer(unsigned(raw_address));
			page_integer := to_integer(unsigned(page));
			if raw_address_integer < 8 then
				return page_integer * 8 + raw_address_integer;
			else
				return raw_address_integer;
			end if;
		end flat_address;
		
		procedure execute_auxiliary_command(command : in std_logic_vector(4 downto 0)) is
		begin
			case command is
				when "00000" => -- immediate execute pon
					pon_pulse <= '1';
				when "00010" => -- chip reset
					-- TODO
				when "00011" => -- release RFD holdoff 
					-- TODO
				when "00100" => -- trigger
					-- TODO
				when "00101" | "01101" => -- rtl 
				when "00110" => -- send EOI on next byte 
					send_eoi := '1';
				when "00111" => -- non-valid pass through secondary address 
					-- TODO
				when "01111" => -- valid pass through secondary address 
					-- TODO
				when "00001" => -- clear parallel poll flag 
					-- TODO
				when "01001" => -- set parallel poll flag 
					-- TODO
				when "10000" => -- go to standby 
					-- TODO
				when "10001" => -- take control asynchronously
					-- TODO
				when "10010" => -- take control synchronously
					-- TODO
				when "11010" => -- take control synchronously on end
					-- TODO
				when "10011" => -- listen (pulse)
					-- TODO
				when "11000" => -- request rsv true
					rsv <= '1';
				when "11001" => -- request rsv false
					rsv <= '0';
				when "11011" => -- listen with continuous mode
					-- TODO
				when "11100" => -- local unlisten (pulse)
				when "11101" => -- execute parallel poll
					-- TODO
				when "10110" => -- clear IFC 
					-- TODO
				when "11110" => -- set IFC 
					-- TODO
				when "10111" => -- clear REN 
					-- TODO
				when "11111" => -- set REN
					-- TODO
				when "10100" => -- disable system control (wrong in cb7210 user manual)
					-- TODO
				when others =>
			end case;
		end execute_auxiliary_command;
		
		-- process a write from the host
		procedure host_write_register (page : in std_logic_vector(3 downto 0);
			write_address : in std_logic_vector(num_address_lines - 1 downto 0);
			write_data : in std_logic_vector(7 downto 0)) is

		begin
			case flat_address(page, write_address) is
				when 0 => -- byte out register
					host_to_gpib_data_byte <= write_data;
					host_to_gpib_data_byte_end <= send_eoi;
					send_eoi := '0';
					do_pulse_host_to_gpib_data_byte_write := true;
				when 1 => -- interrupt mask register 1
					-- TODO
				when 2 => -- interrupt mask register 2
					-- TODO
				when 3 => -- serial poll mode
					local_STB <= write_data;
					rsv <= write_data(6);
				when 4 => -- address mode
					address_mode <= write_data(1 downto 0);
					transmit_receive_mode <= write_data(5 downto 4);
					lon <= write_data(6);
					ton <= write_data(7);
				when 5 => -- auxiliary mode register
					case write_data(7 downto 5) is
						when "000" => -- auxiliary command
							execute_auxiliary_command(write_data(4 downto 0));
						when "001" => -- reference clock frequency
							-- TODO
						when "011" => -- parallel poll register
							-- TODO
						when "100" => -- aux A register
							-- TODO
						when "101" => -- aux B register
							high_speed_T1_delay <= write_data(2);
							-- TODO
						when "110" => -- aux E register
							-- TODO
						when "010" => 
							if write_data(4) = '1' then
								register_page <= write_data(3 downto 0);
							else
								ultra_fast_T1_delay <= write_data(0);
							end if;
						when others =>
					end case;
				when 6 => -- address 0/1
					if to_bit(write_data(7)) = '1' then
						gpib_address_1 <= write_data(4 downto 0);
						enable_listener_gpib_address_1 <= not write_data(5);
						enable_talker_gpib_address_1 <= not write_data(6);
					else
						gpib_address_0 <= write_data(4 downto 0);
						enable_listener_gpib_address_0 <= not write_data(5);
						enable_talker_gpib_address_0 <= not write_data(6);
					end if;
				when 7 => -- end of string
				when 16#e# => -- interrupt mask register 0
				when others =>
			end case;
		end host_write_register;
		
		-- process a write from the host
		procedure host_read_register (page : in std_logic_vector(3 downto 0);
			read_address : in std_logic_vector(num_address_lines - 1 downto 0)) is

		begin
			case flat_address(page, read_address) is
				when 0 => -- data in
					host_data_bus_out_buffer <= gpib_to_host_byte;
					do_pulse_gpib_to_host_byte_read := true;
				when others =>
			end case;
		end host_read_register;
	begin
		if pon = '1' then
			if safe_reset = '1' then
				prev_host_write_selected := '0';
				register_page <= (others => '0');
				latched_address <= (others => '0');
				latched_host_data_byte_in <= (others => '0');
				prev_host_read_selected := '0';
				host_data_bus_out_buffer <= (others => 'Z');
			end if;
			local_STB <= (others => '0');
			rsv <= '0';
			lon <= '0';
			ton <= '0';
			transmit_receive_mode <= "00";
			address_mode <= "00";
			ultra_fast_T1_delay <= '0';
			high_speed_T1_delay <= '0';
			gpib_address_0 <= (others => '0');
			enable_talker_gpib_address_0 <= '0';
			enable_listener_gpib_address_0 <= '0';
			gpib_address_1 <= (others => '0');
			enable_talker_gpib_address_1 <= '0';
			enable_listener_gpib_address_1 <= '0';
			host_to_gpib_data_byte_write <= '0';
			do_pulse_host_to_gpib_data_byte_write := false;
			do_pulse_gpib_to_host_byte_read := false;
			send_eoi := '0';
			-- we have to clear the pon pulse in the "if pon" section
			-- otherwise we will get stuck in pon. We still want to
			-- wait for a clock though.
			if rising_edge(clock) then 
				pon_pulse <= '0';
			end if;
		elsif rising_edge(clock) then
			if host_write_selected = '1' then
				latched_address <= address;
				latched_host_data_byte_in <= host_data_bus_in;
			end if;

			-- process write
			if prev_host_write_selected = '1' and host_write_selected = '0' then
				host_write_register(register_page, latched_address, latched_host_data_byte_in);
				register_page <= (others => '0');
			end if;
			prev_host_write_selected := host_write_selected;

			-- process read
			if prev_host_read_selected = '0' and host_read_selected = '1' then
				host_read_register(register_page, address);
			elsif prev_host_read_selected = '1' and host_read_selected = '0' then -- read has completed	
				register_page <= (others => '0');
			end if;
			prev_host_read_selected := host_read_selected;

			-- handle pulses
			if do_pulse_host_to_gpib_data_byte_write then
				host_to_gpib_data_byte_write <= '1';
				do_pulse_host_to_gpib_data_byte_write := false;
			else
				host_to_gpib_data_byte_write <= '0';
			end if;
			if do_pulse_gpib_to_host_byte_read then
				gpib_to_host_byte_read <= '1';
				do_pulse_gpib_to_host_byte_read := false;
			else
				gpib_to_host_byte_read <= '0';
			end if;				
		end if;
	end process;

	-- set timing counters
	first_T1_terminal_count <= T1_clock_ticks_1100ns when ultra_fast_T1_delay = '1' else
		T1_clock_ticks_2us;
	T1_terminal_count <= T1_clock_ticks_350ns when ultra_fast_T1_delay = '1' else
		T1_clock_ticks_500ns when high_speed_T1_delay = '1' else
		T1_clock_ticks_2us;
	
	-- figure out configured primary/secondary addresses based on settings written
	-- to chip registers
	process (pon, clock)
	begin
		if pon = '1' then
			configured_primary_address <= to_stdlogicvector(NO_ADDRESS_CONFIGURED);
			configured_secondary_address <= to_stdlogicvector(NO_ADDRESS_CONFIGURED);
		elsif rising_edge(clock) then
			case address_mode is
				when "00" =>
					configured_primary_address <= to_stdlogicvector(NO_ADDRESS_CONFIGURED);
					configured_secondary_address <= to_stdlogicvector(NO_ADDRESS_CONFIGURED);
				when "01" =>
					configured_primary_address <= gpib_address_0;
					configured_secondary_address <= to_stdlogicvector(NO_ADDRESS_CONFIGURED);
					-- TODO minor address
				when "10" =>
					configured_primary_address <= gpib_address_0;
					configured_secondary_address <= gpib_address_1;
				when "11" =>
					-- TODO addresses are major/minor primary addresses and secondaries are
					-- done via software using command pass through reg
				when others =>
			end case;
		end if;
	end process;
	
	talk_enable_buffer <= '1' when talker_state_p1 = TACS or talker_state_p1 = SPAS or 
			controller_state_p1 = CACS else
		'0';
	talk_enable <= talk_enable_buffer;
	
	not_controller_in_charge_buffer <= '1' when controller_state_p1 = CIDS or controller_state_p1 = CADS else '0';
	not_controller_in_charge <= not_controller_in_charge_buffer;

	pullup_disable_buffer <= '1' when to_X01(not_controller_in_charge_buffer) = '1' or 
		parallel_poll_state_p1 /= PPAS else '0';
	pullup_disable <= pullup_disable_buffer;
	
	EOI_output_enable_buffer <= '1' when
			talk_enable_buffer = '1' or 
			(controller_state_p1 /= CIDS and controller_state_p1 /= CADS and 
				controller_state_p1 /= CSBS and controller_state_p1 /= CSHS) else
		'0';
	EOI_output_enable <= EOI_output_enable_buffer;

	trigger_buffer <= '1' when device_trigger_state = DTAS else '0';
	trigger <= trigger_buffer;
	
	tr1 <= talk_enable_buffer;
	process (pon, clock)
	begin
		if pon = '1' then
			tr2 <= '0';
			tr3 <= '0';
		elsif rising_edge(clock) then
			case transmit_receive_mode is
				when "00" =>
					tr2 <= EOI_output_enable_buffer;
					tr3 <= trigger_buffer;
				when "01" =>
					tr2 <= not not_controller_in_charge_buffer;
					tr3 <= trigger_buffer;
				when "10" =>
					tr2 <= not not_controller_in_charge_buffer;
					tr3 <= EOI_output_enable_buffer;
				when "11" =>
					tr2 <= not not_controller_in_charge_buffer;
					tr3 <= pullup_disable_buffer;
				when others =>
					tr2 <= 'X';
					tr3 <= 'X';
			end case;
		end if;
	end process;
end frontend_cb7210p2_arch;
