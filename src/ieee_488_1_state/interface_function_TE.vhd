-- IEEE 488.1 extended talker TE and talker T interface functions.  Implements TE5 and T5.
--
-- Author: Frank Mori Hess fmh6jj@gmail.com
-- Copyright Frank Mori Hess 2017


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.interface_function_common.all;

entity interface_function_TE is
	port(
		clock : in std_logic;
		acceptor_handshake_state : in AH_state;
		listener_state_p2 : in LE_state_p2;
		service_request_state : in SR_state;
		source_handshake_state : in SH_state;
		ATN : in std_logic;
		IFC : in std_logic;
		pon : in std_logic;
		ton : in std_logic;
		MTA : in std_logic;
		MSA : in std_logic;
		OTA : in std_logic;
		OSA : in std_logic;
		MLA : in std_logic;
		SPE : in std_logic;
		SPD : in std_logic;
		PCG : in std_logic;
		enable_secondary_addressing : in std_logic; -- true for extended talker, false for talker
		host_to_gpib_data_byte_end : in std_logic;
		assert_END_in_SPAS : in std_logic;
		
		talker_state_p1 : out TE_state_p1;
		talker_state_p2 : out TE_state_p2;
		talker_state_p3 : out TE_state_p3;
		END_msg : out std_logic;
		RQS : out std_logic;
		NUL : out std_logic
	);
 
end interface_function_TE;
 
architecture interface_function_TE_arch of interface_function_TE is
 
	signal talker_state_p1_buffer : TE_state_p1;
	signal talker_state_p2_buffer : TE_state_p2;
	signal talker_state_p3_buffer : TE_state_p3;
	signal TE_addressed : boolean;
	signal T_addressed : boolean;
	signal addressed : boolean;
	signal TE_unaddressed : boolean;
	signal T_unaddressed : boolean;
	signal unaddressed : boolean;
	signal latched_end : std_logic;
	
begin
 
	talker_state_p1 <= talker_state_p1_buffer;
	talker_state_p2 <= talker_state_p2_buffer;
	talker_state_p3 <= talker_state_p3_buffer;
	
	T_addressed <= to_bit(IFC) = '0' and to_bit(MTA) = '1' and acceptor_handshake_state = ACDS;	
	TE_addressed <= to_bit(IFC) = '0' and to_bit(MSA) = '1' and talker_state_p2_buffer = TPAS and acceptor_handshake_state = ACDS;
	addressed <= (to_bit(IFC) = '0' and to_bit(ton) = '1') or ((to_bit(enable_secondary_addressing) = '1' and TE_addressed) or
		(to_bit(enable_secondary_addressing) = '0' and T_addressed));

	T_unaddressed <= to_bit(OTA or MLA) = '1';
	TE_unaddressed <= to_bit(OTA) = '1' or 
		(to_bit(OSA) = '1' and talker_state_p2_buffer = TPAS) or (to_bit(MSA) = '1' and listener_state_p2 = LPAS);
	unaddressed <= acceptor_handshake_state = ACDS and 
		((to_bit(enable_secondary_addressing) = '1' and TE_unaddressed) or
		(to_bit(enable_secondary_addressing) = '0' and T_unaddressed));

	
	process(pon, clock) begin
		if pon = '1' then
			talker_state_p1_buffer <= TIDS;
			talker_state_p2_buffer <= TPIS;
			talker_state_p3_buffer <= SPIS;
			latched_end <= '0';
		elsif rising_edge(clock) then

			-- part 1 state machine
			case talker_state_p1_buffer is
				when TIDS =>
					if addressed then
						talker_state_p1_buffer <= TADS;
					end if;
				when TADS =>
					if unaddressed then
						talker_state_p1_buffer <= TIDS;
					elsif to_bit(ATN) = '0' then
						if talker_state_p3_buffer /= SPMS then
							talker_state_p1_buffer <= TACS;
						else
							talker_state_p1_buffer <= SPAS;
						end if;
					end if;
				when TACS =>
					if to_bit(ATN) = '1' then
						talker_state_p1_buffer <= TADS;
					end if;
				when SPAS =>
					if to_bit(ATN) = '1' then
						talker_state_p1_buffer <= TADS;
					end if;
			end case;

			-- part 2 state machine
			case talker_state_p2_buffer is
				when TPIS =>
					if to_bit(MTA) = '1' and acceptor_handshake_state = ACDS then
						talker_state_p2_buffer <= TPAS;
					end if;
				when TPAS =>
					if to_bit(PCG) = '1' and to_bit(MTA) = '0' and acceptor_handshake_state = ACDS then
						talker_state_p2_buffer <= TPIS;
					end if;
			end case;

			-- part 3 state machine
			case talker_state_p3_buffer is
				when SPIS =>
					if to_bit(not IFC and SPE) = '1' and acceptor_handshake_state = ACDS then
						talker_state_p3_buffer <= SPMS;
					end if;
				when SPMS =>
					if to_bit(SPD) = '1' and acceptor_handshake_state = ACDS then
						talker_state_p3_buffer <= SPIS;
					end if;
			end case;

			if to_bit(IFC) = '1' then
				talker_state_p1_buffer <= TIDS;
				talker_state_p3_buffer <= SPIS;
			end if;
	
			if source_handshake_state /= STRS then
				latched_end <= host_to_gpib_data_byte_end;
			end if;
		end if;
	end process;
	
	-- set local message outputs as soon as state changes for low latency
	process(talker_state_p1_buffer, source_handshake_state, service_request_state, latched_end) 
	begin
		-- part 1 state machine
		case talker_state_p1_buffer is
			when TIDS =>
				END_msg <= 'L';
				RQS <= 'L';
				NUL <= 'H';
			when TADS =>
				END_msg <= 'L';
				RQS <= 'L';
				NUL <= 'H';
			when TACS =>
				if source_handshake_state = SDYS or source_handshake_state = STRS then  
					END_msg <= latched_end;
				else
					END_msg <= 'L';
				end if;
				RQS <= 'L';
				NUL <= 'L';
			when SPAS =>
				END_msg <= assert_END_in_SPAS;
				if service_request_state = APRS then
					RQS <= '1';
				else
					RQS <= '0';
				end if;
				NUL <= 'L';
		end case;
	end process;
	
end interface_function_TE_arch;
