library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hash_message is
    port(
        clk   : in std_logic;
        reset : in std_logic;
        d     : in hash_message_input_type;
        q     : out hash_message_output_type);
end hash_message;

architecture Behavioral of hash_message is
    alias m_in : hash_message_input_type_small is d.module_input;
    alias m_out : hash_message_output_type_small is q.module_output;
        
    type state_type is (S_IDLE, S_HASH_MESSAGE_INIT, S_HASH_MESSAGE_CORE, S_WAIT, S_ABSORB_R, S_ABSORB_INDEX, S_ABSORB_ROOT, S_ABSORB_MESSAGE);
    type reg_type is record
        state : state_type;
        ctr : integer range 0 to 1023;
        mhash : std_logic_vector(n*8-1 downto 0);
    end record;
    
    signal bram_select : unsigned(1 downto 0);
    signal hash_select : unsigned(1 downto 0);
    signal r, r_in : reg_type;
begin

    q.hash.len <= 4*8*n + m_in.mlen;
    q.hash.id.ctr <= to_unsigned(0, ID_CTR_LEN);
    q.hash.id.block_ctr <= "000";
    q.bram.en <= '1';
    q.bram.wen <= '0';
    q.bram.din <= (others => '0');
    m_out.mhash <= r.mhash;

    combinational : process (r, d)
	   variable v : reg_type;
	begin
	    v := r;
	    m_out.done <= '0';
	    q.hash.enable <= '0';
	    bram_select <= "00";
	    hash_select <= "00";

        case r.state is
           when S_IDLE =>
               if m_in.enable = '1' then
                   v.ctr := 0;
                   v.state := S_HASH_MESSAGE_INIT;
               end if;                  
             when S_HASH_MESSAGE_INIT =>
                   q.hash.enable <= '1';
                   v.state := S_ABSORB_R;
             when S_ABSORB_R =>
                   hash_select <= "01";
                   if d.hash.mnext = '1' then v.state := S_ABSORB_ROOT; end if;
             when S_ABSORB_ROOT =>
                   hash_select <= "01";
                   bram_select <= "01"; 
                   if d.hash.mnext = '1' then v.state := S_ABSORB_INDEX; end if;
             when S_ABSORB_INDEX =>
                  hash_select <= "10";
                  if d.hash.mnext = '1' then v.state := S_ABSORB_MESSAGE; end if;
             when S_ABSORB_MESSAGE =>
                  hash_select <= "01";
                  bram_select <= "10";
                  if d.hash.mnext = '1' then v.ctr := r.ctr + 1; end if;
                  if d.hash.done = '1' then
                      v.mhash := d.hash.o;
                      m_out.done <= '1';
                      v.state := S_IDLE;
                  end if;     
              when others => null;	          
        end case;
     	r_in <= v;
    end process; 
    
    hash_mux : process(hash_select, m_in.index, d.bram.dout)
    begin
        case hash_select is
            when "00" => q.hash.input <= std_logic_vector(to_unsigned(2, n*8));
            when "10" => q.hash.input <= std_logic_vector(resize(m_in.index, n*8));
            when others => q.hash.input <= d.bram.dout;
        end case;
    end process;

    bram_mux : process(bram_select, r.ctr)
    begin
        case bram_select is
            when "00" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG + 1, BRAM_ADDR_SIZE));
            when "01" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_PK, BRAM_ADDR_SIZE));
            when "10" => q.bram.addr <= std_logic_vector(to_unsigned(BRAM_MESSAGE + r.ctr, BRAM_ADDR_SIZE));
            when others => q.bram.addr <= (others => '0');
        end case;
    end process;
    
    sequential : process(clk)
	begin
	   if rising_edge(clk) then
	    if reset = '1' then
	       r.state <= S_IDLE;
           -- FIX: Resetear ctr y mhash
           r.ctr <= 0;
           r.mhash <= (others => '0');
	    else
		   r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;