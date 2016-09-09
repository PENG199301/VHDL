-----------------------------------------------------------------
--! @file 
--! @brief I2c_slave_engine : 
--! @details This entity with synchronization reset is used to simulate the whole slave engine 
--! design with register. By the way, those ports is simulated for the part of register insteading 
--! of Avalon interface. According to the I2C slave engine, we need to use some components what it needs
--! to work well.
--! 
--! PENG Donghui
-----------------------------------------------------------------




--! Use standard library
library ieee;
--! Use logic elements
use ieee.std_logic_1164.all;

--!
entity I2c_slave_engine is

port(
		clk: in std_logic;				
		clk_ena: in std_logic;			
		sync_rst: in std_logic;		
		SCL_in	: in STD_LOGIC;
		SDA_in	: in STD_LOGIC;
		
		
		ctl_role_r: in std_logic;
		ctl_ack_r: in std_logic;
		ctl_reset_r: in std_logic;
		
		
		status_rxfull_r: in std_logic;
		status_txempty_r: in std_logic;		
		
		
		txdata: in std_logic_vector (7 downto 0);
		
		address: in std_logic_vector (6 downto 0);
		
		sda_out	: out STD_LOGIC;

		status_busy_w: out std_logic;
		status_rw_w: out std_logic;
		status_stop_detected_s: out std_logic;
		status_start_detected_s: out std_logic;
		status_error_detected_s: out std_logic;
		status_rxfull_s: out std_logic;
		status_txempty_s: out std_logic;
		status_ackrec_w: out std_logic;
		
		rxdata: out std_logic_vector (7 downto 0)
		
	  );


end entity I2c_slave_engine;


--! Moore & Mealy Combined Machine
architecture fsm of I2c_slave_engine is

	
	signal casc_in 					: STD_LOGIC:= '1';
	signal count 					:integer;
	signal casc_out					: STD_LOGIC;
	signal SCL_tick					: STD_LOGIC; 
	signal sda_out_t1				: STD_LOGIC;
	signal sda_out_r1				: STD_LOGIC;
	signal sda_out_r2				: STD_LOGIC;
	
	
	signal SCL_rising_point 		: STD_LOGIC;
	signal SCL_stop_point			: STD_LOGIC;
	signal SCL_sample_point 		: STD_LOGIC;
	signal SCL_start_point 			: STD_LOGIC;
	signal SCL_falling_point 		: STD_LOGIC;
	signal SCL_write_point 			: STD_LOGIC;
	signal SCL_error_indication 	: STD_LOGIC;
	
	signal receiver1_switch			: STD_LOGIC:='0';
	signal receiver2_switch			: STD_LOGIC:='0';
	signal transmitter1_switch		: STD_LOGIC:='0';
	signal ACK_out					: STD_LOGIC;
	signal ACK_valued			   	: STD_LOGIC;
	signal TX_captured				: STD_LOGIC;
	signal ACK_sent1					: STD_LOGIC;
	signal ACK_sent2					: STD_LOGIC;
	
	signal data_received1			: STD_LOGIC;
	signal RX1				: std_logic_vector (7 downto 0);	
	signal start_detected_point		: STD_LOGIC;
	signal stop_detected_point		: STD_LOGIC;
	signal error_detected_point		: STD_LOGIC;
						
	signal address_received: std_logic_vector (6 downto 0);	
	signal rw_received: STD_LOGIC;

type state_type is (INIT, start, receiver1,receiver1_waiting, receiver2, transmitter1, stop, error );
signal state: state_type := INIT;

	
	component cascadable_counter is

	generic(max_count: positive := 2);
	port (clk: in std_logic;
			ena: in std_logic;
			sync_rst:in std_logic;
			casc_in: in std_logic;
			count: out integer range 0 to (max_count-1);
			casc_out: out std_logic
			);
			
	end component cascadable_counter;
	
	component scl_tick_generator is

	generic( max_count: positive := 8
			);
	
	port(clk_50MHz: in std_logic;	--! clock input
		sync_rst: in std_logic;		--! '0' active synchronous reset input
		ena: in std_logic;			--! clock enable input
		scl_tick: out std_logic		--! scl tick output
		);
		
	end component scl_tick_generator;
	
	

	--! Component Shift register transmitter
	component shift_register_transmitter is

	port(clk: in std_logic;
		  clk_ena: in std_logic;
		  sync_rst: in std_logic;
		  TX: in std_logic_vector (7 downto 0);		-- To connect with TX register
		  rising_point: in std_logic;
		  sampling_point: in std_logic;
		  falling_point: in std_logic;
		  writing_point: in std_logic;
		  scl_tick: in std_logic;
		  sda_in: in std_logic;
		  ACK_out: out std_logic;
		  ACK_valued: out std_logic;
		  TX_captured: out std_logic;
		  sda_out: out std_logic);				
		  
	end component shift_register_transmitter;
	
	
	--! Component Shift register receiver
	component shift_register_receiver is
	port(clk: in std_logic;
	 clk_ena: in std_logic;
	 sync_rst: in std_logic;
	 scl_tick: in std_logic;
	 sda_in: in std_logic;
	 falling_point: in std_logic;
	 sampling_point: in std_logic;
	 writing_point: in std_logic;
	 ACK_in: in std_logic;
	 sda_out: out std_logic;
	 ACK_sent: out std_logic;		--! ACK_sent output, triger a '1' when ACK is sent
	 data_received: out std_logic;
	 RX: out std_logic_vector (7 downto 0));
	 
	end component shift_register_receiver;
	
	
	component Condition_detect is
	port(
    clk						: in STD_LOGIC;--! clock input
	clk_ena					: in STD_LOGIC;--! clock_enable input
	sync_rst				: in STD_LOGIC;--! synchronization reset input
	SCL_in 			        : in STD_LOGIC;--! I2C clock line input
    SDA_in             		: in STD_LOGIC;--! I2C data line input
	 
    start_detected_point    : out  STD_LOGIC;--! detected start condition 
	stop_detected_point     : out  STD_LOGIC;--! detected stop condition
	error_detected_point    : out  STD_LOGIC --! detected error condition
	); 
	 
	end component Condition_detect;
	
	
	component SCL_detect is
	Port( 
        clk 					:in  STD_LOGIC;--! clock input
        clk_ena 				:in  STD_LOGIC;--! clock_enable input
		sync_rst 				:in  STD_LOGIC;--! synchronization reset input
        SCL_in 					:in  STD_LOGIC;--! I2C clock line input
		SCL_tick 				:in  STD_LOGIC;--! tick clock line input
			  
		SCL_rising_point 		:out  STD_LOGIC;--! detected SCL_rising_point 
		SCL_stop_point 			:out  STD_LOGIC;--! detected SCL_stop_point 
		SCL_sample_point 		:out  STD_LOGIC;--! detected SCL_sample_point 
		SCL_start_point 		:out  STD_LOGIC;--! detected SCL_start_point 
		SCL_falling_point 		:out  STD_LOGIC;--! detected SCL_falling_point 
		SCL_write_point 		:out  STD_LOGIC;--! detected SCL_write_point 
		SCL_error_indication 	:out  STD_LOGIC --! detected SCL_error_indication 
		);
          
	end component SCL_detect;
	
begin
	
	cc: cascadable_counter
	 port map(clk => clk,
	 ena => clk_ena,
	 sync_rst => sync_rst,
	 casc_in => casc_in,
	 count=>count,
	 casc_out=>casc_out
	 );
	
	Stg: scl_tick_generator
	 port map(clk_50MHz => clk,
	 sync_rst => sync_rst,
	 ena => casc_out,
	 scl_tick => scl_tick
	 );
	
	
	
	t1: shift_register_transmitter
	port map(clk => clk,
		  clk_ena => clk_ena,
		  sync_rst => transmitter1_switch,
		  TX => txdata,		-- To connect with TX register
		  rising_point => SCL_rising_point,
		  sampling_point => SCL_sample_point,
		  falling_point => SCL_falling_point,
		  writing_point => SCL_write_point,
		  scl_tick => scl_tick,
		  sda_out => sda_out_t1,
		  sda_in => sda_in,
		  ACK_out => status_ackrec_w,
		  ACK_valued => ACK_valued,
		  TX_captured => status_txempty_s);
	
	
	 r1: shift_register_receiver
	 port map(clk => clk,
	 clk_ena => clk_ena,
	 sync_rst => receiver1_switch,
	 scl_tick => scl_tick,
	 sda_in => sda_in,
	 falling_point => SCL_falling_point,
	 sampling_point => SCL_sample_point,
	 writing_point => SCL_write_point,
	 ACK_in => ctl_ack_r,
	 sda_out => sda_out_r1, 				--sda_out,
	 ACK_sent=> ACK_sent1,
	 data_received => data_received1,
	 RX => RX1);
	 
	 
	 r2: shift_register_receiver
	 port map(clk => clk,
	 clk_ena => clk_ena,
	 sync_rst => receiver2_switch,
	 scl_tick => scl_tick,
	 sda_in => sda_in,
	 falling_point => SCL_falling_point,
	 sampling_point => SCL_sample_point,
	 writing_point => SCL_write_point,
	 ACK_in => ctl_ack_r,
	 sda_out => sda_out_r2, 				--sda_out,
	 ACK_sent=> ACK_sent2,
	 data_received => status_rxfull_s,
	 RX => rxdata);
	 
	 Cd: Condition_detect
	 port map(clk => clk,
	 clk_ena => clk_ena,
	 sync_rst => sync_rst,
	 SCL_in => scl_in,
	 SDA_in => SDA_in,
	 start_detected_point => start_detected_point,
	 stop_detected_point => stop_detected_point,
	 error_detected_point => error_detected_point
	 );
	 
	 
	Sd: SCL_detect
	port map(  
			sync_rst => sync_rst,
			clk => clk, 
			clk_ena => clk_ena, 
			SCL_in => scl_in,
			SCL_tick => SCL_tick,
				
			SCL_stop_point => SCL_stop_point,
			SCL_start_point => SCL_start_point,
			SCL_rising_point => SCL_rising_point,
			SCL_falling_point => SCL_falling_point,
			SCL_sample_point => SCL_sample_point,
			SCL_write_point => SCL_write_point,
			SCL_error_indication => SCL_error_indication
			);


			
transitions_and_storage: process (clk) is
	
begin 

if(rising_edge(clk)) then
	if(clk_ena = '1') then
		if(sync_rst = '1') then
			
				if(ctl_role_r = '0') then
					case state is	 
						
					when INIT =>
						if (start_detected_point = '1') then 
							state <= start;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
					
					when start =>
						if (SCL_falling_point= '1') then
						state <= receiver1;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
							
					when receiver1 =>
						
						if  (ACK_sent1 = '1') then
							state <= receiver1_waiting;
						
						else 
							state <= receiver1;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
					
					when receiver1_waiting=>
						if(address = address_received) then 
								if (rw_received = '0') then 
								state <= receiver2;
								end if;
							
								if (rw_received = '1') then 
								state <= transmitter1;
								end if;
						else
								state <= INIT;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
						
					when receiver2 => 
						if (stop_detected_point = '1') then 
							state <= stop;
						else 
							state <= receiver2;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
						
					when transmitter1 => 
						if (stop_detected_point = '1') then 
							state <= stop;
						else
							state <= transmitter1;
						end if;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
					
					when stop => 
						state <= INIT;
						
						if ((SCL_error_indication = '1') or (error_detected_point = '1')) then 
							state <= error;
						end if;
					
					when error => 
						if(sync_rst = '0') then 
							state <= init;
						end if;
					
					end case;
				end if;
			
		else
			state <= INIT;
		end if;
	end if;
end if;

end process transitions_and_storage;	 




stateaction: process (state) is
	
begin
		receiver1_switch <= '0';
		receiver2_switch <= '0';
		transmitter1_switch <= '0';
		
        status_busy_w <= '1';
		status_rw_w <= rw_received;
		status_stop_detected_s <= '0';
		status_start_detected_s <= '0';
		status_error_detected_s <= '0';
		
		
		
			
case state is
		
		when INIT => 
			status_busy_w <= '0';	
		
		when start => 
			status_start_detected_s <= '1';	
			
			
		when receiver1 =>
			
			receiver1_switch <= '1';
			
		when receiver1_waiting => 
			receiver1_switch <= '1';	
			rw_received <= RX1(0);
			address_received <= RX1(7 downto 1);
			
		
		when receiver2 => 
			receiver2_switch <= '1';
			
			
		when transmitter1 => 
			transmitter1_switch <= '1';

		when stop =>
			status_busy_w <= '0';
			status_stop_detected_s <= '1';
				
		when error =>
			status_error_detected_s <= '1';	
					
		end case;
	
	end process stateaction;
	
	
	
sda_out <= sda_out_r1 and sda_out_r2 and sda_out_t1;
	
	
end architecture fsm;

