-- a cb7210 with digital filtering of the gpib control lines,
-- and dma translation suitable for an ARM PL330 DMA controller.
-- There is also a "gpib_disable" input which disconnects the
-- gpib chip from the gpib bus, and a dma transfer counter.
--
-- Author: Frank Mori Hess fmh6jj@gmail.com
-- Copyright 2017 Frank Mori Hess
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dma_translator_cb7210p2_to_pl330;
use work.gpib_control_debounce_filter;
use work.frontend_cb7210p2;

entity gpib_top is
	port (
		clk : in std_logic;
		reset : in  std_logic;

		-- gpib chip registers, avalon mm io port
		avalon_cs : in std_logic; -- inverted
		avalon_rd : in std_logic; -- inverted
		avalon_wr : in  std_logic; -- inverted
		avalon_addr : in  std_logic_vector(2 downto 0);
		avalon_din : in  std_logic_vector(7 downto 0);
		avalon_dout : out std_logic_vector(7 downto 0);

		avalon_irq : out std_logic;

		-- dma, avalon mm io port
		dma_cs : in std_logic; -- inverted
		dma_rd : in std_logic; --inverted
		dma_wr : in std_logic; --inverted
		dma_din : in  std_logic_vector(7 downto 0);
		dma_dout : out std_logic_vector(7 downto 0);
		-- dma request
		dma_single : out std_logic; -- request single transfer
		dma_req : out std_logic; -- request burst transfer
		dma_ack : in  std_logic;

		-- transfer counter, avalon mm io port
		dma_count_cs : in std_logic; -- inverted
		dma_count_rd : in  std_logic; -- inverted
		dma_count_wr : in  std_logic; -- inverted
		dma_count_din : in  std_logic_vector(10 downto 0);
		dma_count_dout : out std_logic_vector(10 downto 0);

		-- gpib bus
		gpib_data : inout std_logic_vector (7 downto 0);
		gpib_atn : inout std_logic;
		gpib_dav : inout std_logic;
		gpib_eoi : inout std_logic;
		gpib_ifc : inout std_logic;
		gpib_nrfd : inout std_logic;
		gpib_ndac : inout std_logic;
		gpib_srq : inout std_logic;
		gpib_ren : inout std_logic;

		-- gpib transceiver control
		gpib_pe : out std_logic;
		gpib_dc : out std_logic;
		gpib_te : out std_logic;

		-- gpib bus disconnect
		gpib_disable : in std_logic
	);
end gpib_top;

architecture structural of gpib_top is
	signal safe_reset : std_logic;
	
	signal cb7210p2_dma_bus_in_request : std_logic;
	signal cb7210p2_dma_bus_out_request : std_logic;
	signal cb7210p2_dma_read_inverted : std_logic;
	signal cb7210p2_dma_write_inverted : std_logic;
	signal cb7210p2_dma_ack_inverted : std_logic;
	
	signal dma_count: unsigned (10 downto 0); -- Count of bytes into 7210.
	signal dma_transfer_active : std_logic;
	
	signal filtered_ATN : std_logic;
	signal filtered_DAV : std_logic;
	signal filtered_EOI : std_logic;
	signal filtered_IFC : std_logic;
	signal filtered_NDAC : std_logic;
	signal filtered_NRFD : std_logic;
	signal filtered_REN : std_logic;
	signal filtered_SRQ : std_logic;

	-- gpib control line inputs gated by gpib_disable.  We don't need to disable input gpib data lines.
	signal gated_ATN : std_logic;
	signal gated_DAV : std_logic;
	signal gated_EOI : std_logic;
	signal gated_IFC : std_logic;
	signal gated_NDAC : std_logic;
	signal gated_NRFD : std_logic;
	signal gated_REN : std_logic;
	signal gated_SRQ : std_logic;
	
	-- raw gpib control lines and data coming from the gpib chip, before they have been gated by gpib_disable
	signal ungated_ATN_inverted_out : std_logic;
	signal ungated_DAV_inverted_out : std_logic;
	signal ungated_EOI_inverted_out : std_logic;
	signal ungated_IFC_inverted_out : std_logic;
	signal ungated_NDAC_inverted_out : std_logic;
	signal ungated_NRFD_inverted_out : std_logic;
	signal ungated_REN_inverted_out : std_logic;
	signal ungated_SRQ_inverted_out : std_logic;
	signal ungated_DIO_inverted_out : std_logic_vector(7 downto 0);
	
	-- raw transceiver controls
	signal ungated_talk_enable : std_logic;
	signal ungated_pullup_disable : std_logic;
	signal ungated_not_controller_in_charge : std_logic;
	
begin
	my_dma_translator : entity work.dma_translator_cb7210p2_to_pl330
		port map (
			clock => clk,
			reset => safe_reset,
			pl330_dma_ack => dma_ack,
			pl330_dma_single => dma_single,
			pl330_dma_req => dma_req,
			cb7210p2_dma_in_request => cb7210p2_dma_bus_in_request,
			cb7210p2_dma_out_request => cb7210p2_dma_bus_out_request
		);
	
	my_debounce_filter : entity work.gpib_control_debounce_filter
		generic map(
			length => 12,
			threshold => 10
		)
		port map(
			reset => safe_reset,
			input_clock => clk,
			output_clock => clk,
			inputs(0) => gpib_atn,
			inputs(1) => gpib_dav,
			inputs(2) => gpib_eoi,
			inputs(3) => gpib_ifc,
			inputs(4) => gpib_ndac,
			inputs(5) => gpib_nrfd,
			inputs(6) => gpib_ren,
			inputs(7) => gpib_srq,
			outputs(0) => filtered_ATN,
			outputs(1) => filtered_DAV,
			outputs(2) => filtered_EOI,
			outputs(3) => filtered_IFC,
			outputs(4) => filtered_NDAC,
			outputs(5) => filtered_NRFD,
			outputs(6) => filtered_REN,
			outputs(7) => filtered_SRQ
		);
	
	my_cb7210p2 : entity work.frontend_cb7210p2
		generic map(
			num_address_lines => 3,
			clock_frequency_KHz => 60000)
		port map (
			clock => clk,
			reset => safe_reset,
			chip_select_inverted => avalon_cs,
			dma_bus_in_ack_inverted => cb7210p2_dma_ack_inverted,
			dma_bus_out_ack_inverted => cb7210p2_dma_ack_inverted,
			dma_read_inverted => cb7210p2_dma_read_inverted,
			dma_write_inverted => cb7210p2_dma_write_inverted,
			read_inverted => avalon_rd,
			address => avalon_addr(2 downto 0),
			write_inverted => avalon_wr,
			host_data_bus_in => avalon_din,
			dma_bus_in => dma_din,
			gpib_ATN_inverted_in => gated_ATN,
			gpib_DAV_inverted_in => gated_DAV,
			gpib_EOI_inverted_in => gated_EOI,
			gpib_IFC_inverted_in => gated_IFC,
			gpib_NDAC_inverted_in => gated_NDAC,
			gpib_NRFD_inverted_in => gated_NRFD,
			gpib_REN_inverted_in => gated_REN,
			gpib_SRQ_inverted_in => gated_SRQ,
			gpib_DIO_inverted_in => gpib_data,
			tr1 => ungated_talk_enable,
			not_controller_in_charge => ungated_not_controller_in_charge,
			pullup_disable => ungated_pullup_disable,
			interrupt => avalon_irq,
			dma_bus_in_request => cb7210p2_dma_bus_in_request,
			dma_bus_out_request => cb7210p2_dma_bus_out_request,
			host_data_bus_out => avalon_dout,
			dma_bus_out => dma_dout,
			gpib_ATN_inverted_out => ungated_ATN_inverted_out,
			gpib_DAV_inverted_out => ungated_DAV_inverted_out,
			gpib_EOI_inverted_out => ungated_EOI_inverted_out,
			gpib_IFC_inverted_out => ungated_IFC_inverted_out,
			gpib_NDAC_inverted_out => ungated_NDAC_inverted_out,
			gpib_NRFD_inverted_out => ungated_NRFD_inverted_out,
			gpib_REN_inverted_out => ungated_REN_inverted_out,
			gpib_SRQ_inverted_out => ungated_SRQ_inverted_out,
			gpib_DIO_inverted_out => ungated_DIO_inverted_out
		);

	dma_count_dout <= std_logic_vector(dma_count);

	-- sync reset deassertion
	process (reset, clk)
	begin
		if to_X01(reset) = '1' then
			safe_reset <= '1';
		elsif rising_edge(clk) then
			safe_reset <= '0';
		end if;
	end process;
	
	-- dma transfer counter
	process(safe_reset, clk) is
		variable prev_dma_cs : std_logic;
	begin
		if safe_reset = '1' then
			dma_count <= (others => '0');
			prev_dma_cs := '1';
		elsif rising_edge(clk) then
			-- Reset counter when written to.
			if (dma_count_cs = '0') and (dma_count_wr = '0') then
				dma_count <= (others => '0');
			-- count bytes on data transfer across dma bus port.
			elsif dma_cs = '0' and prev_dma_cs = '1' then
				dma_count <= dma_count + 1;
			end if;
			prev_dma_cs := dma_cs;
		end if;
	end process;

	-- handle gating by gpib_disable
	process (safe_reset, clk)
	begin
		if to_X01(safe_reset) = '1' then
			-- inputs
			gated_ATN <= '1';
			gated_DAV <= '1';
			gated_EOI <= '1';
			gated_IFC <= '1';
			gated_NDAC <= '1';
			gated_NRFD <= '1';
			gated_REN <= '1';
			gated_SRQ <= '1';

			-- transceiver control
			gpib_te <= '0';
			gpib_pe <= '0';
			gpib_dc <= '0';
		elsif rising_edge(clk) then
			if to_X01(gpib_disable) = '1' then
				-- inputs
				gated_ATN <= '1';
				gated_DAV <= '1';
				gated_EOI <= '1';
				gated_IFC <= '1';
				gated_NDAC <= '1';
				gated_NRFD <= '1';
				gated_REN <= '1';
				gated_SRQ <= '1';

				-- transceiver control
				gpib_te <= '0';
				gpib_pe <= '0';
				gpib_dc <= '0';
			else
				-- inputs
 				gated_ATN <= filtered_ATN;
 				gated_DAV <= filtered_DAV;
 				gated_EOI <= filtered_EOI;
 				gated_IFC <= filtered_IFC;
 				gated_NDAC <= filtered_NDAC;
 				gated_NRFD <= filtered_NRFD;
 				gated_REN <= filtered_REN;
 				gated_SRQ <= filtered_SRQ;

				-- transceiver control
				gpib_te <= ungated_talk_enable;
				gpib_pe <= ungated_pullup_disable;
				gpib_dc <= not ungated_not_controller_in_charge;
			end if;
		end if;
	end process;

	gpib_data <= (others => 'Z') when gpib_disable = '1' else ungated_DIO_inverted_out;
	gpib_atn <= 'Z' when gpib_disable = '1' else ungated_ATN_inverted_out;
	gpib_dav <= 'Z' when gpib_disable = '1' else ungated_DAV_inverted_out;
	gpib_eoi <= 'Z' when gpib_disable = '1' else ungated_EOI_inverted_out;
	gpib_ifc <= 'Z' when gpib_disable = '1' else ungated_IFC_inverted_out;
	gpib_ndac <= 'Z' when gpib_disable = '1' else ungated_NDAC_inverted_out;
	gpib_nrfd <= 'Z' when gpib_disable = '1' else ungated_NRFD_inverted_out;
	gpib_ren <= 'Z' when gpib_disable = '1' else ungated_REN_inverted_out;
	gpib_srq <= 'Z' when gpib_disable = '1' else ungated_SRQ_inverted_out;
	
	-- dma port
	cb7210p2_dma_read_inverted <= dma_rd;
	cb7210p2_dma_write_inverted <= dma_wr;
	cb7210p2_dma_ack_inverted <= dma_cs;
end architecture structural;
