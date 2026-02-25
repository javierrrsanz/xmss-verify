library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;
use IEEE.NUMERIC_STD.ALL;

entity xmss_verify is
    port(
        clk   : in std_logic;
        reset : in std_logic;
        d     : in xmss_verify_input_type;
        q     : out xmss_verify_output_type);
end xmss_verify;

architecture Behavioral of xmss_verify is    
    type state_type is (S_IDLE, S_HASH_MESSAGE, S_WOTS_VRFY, S_LTREE, S_COMP_ROOT, S_LOAD_DATA_1, S_LOAD_DATA_2, S_LOAD_DATA_3);
    type bram_type_b is (B_INDEX, B_PUB_SEED, B_ROOT);
    
    type reg_type is record
        state : state_type;
        index : unsigned(tree_height-1 downto 0);
        bram_state_b : bram_type_b;
    end record;

    signal compute_root : xmss_compute_root_input_type;
    signal r, r_in : reg_type;
    signal modules_root_q : xmss_compute_root_output_type;

begin
    
    comproot : entity work.compute_root
	port map(
		clk     => clk,
		reset   => reset,
		d       => compute_root,
		q       => modules_root_q);

    compute_root.leaf <= d.l_tree.leaf_node;
    compute_root.leaf_idx <= to_integer(r.index);
    compute_root.thash <= d.thash;
    compute_root.bram <= d.bram.a;

	q.bram.a <= modules_root_q.bram;
    q.bram.b.en <= '1';
    q.bram.b.wen <= '0';
    q.bram.b.din <= (others => '-');
    
    q.thash <= modules_root_q.thash;
    q.hash_message.mlen <=  d.mlen;
    q.hash_message.index <= r.index;
    q.l_tree.address_4 <= std_logic_vector(resize(r.index, 32));
    
    q.wots.mode <= "10"; 
    q.wots.message <= d.hash_message.mhash;
    q.wots.seed <= (others => '-');
	q.wots.address_4 <= std_logic_vector(resize(r.index, 32));

    combinational : process (r, d, modules_root_q)
	   variable v : reg_type;   
	begin
	    v := r;
	    
	   	q.mode_select_l1 <= "00";
	   	q.valid <= '0';
	   	q.done <= '0';
	   	q.hash_message.enable <= '0';
	   	q.l_tree.enable <= '0';
	   	q.wots.enable <= '0';
	   	compute_root.enable <= '0';

	   	case r.state is
	       when S_IDLE =>
	           if d.enable = '1' then
	               v.bram_state_b := B_INDEX;
	               v.state := S_LOAD_DATA_1;
	           end if;
	           
	       when S_LOAD_DATA_1 => 
	           v.state := S_LOAD_DATA_2;

	       when S_LOAD_DATA_2 =>
	           v.state := S_LOAD_DATA_3;

	       when S_LOAD_DATA_3 =>
	           v.index := unsigned(d.bram.b.dout(tree_height - 1 downto 0));
	           v.bram_state_b := B_PUB_SEED;
	           v.state := S_HASH_MESSAGE;

	       when S_HASH_MESSAGE => 
	           q.mode_select_l1 <= "10";
	           q.hash_message.enable <= '1';
	           if d.hash_message.done = '1' then	                   
	               v.state := S_WOTS_VRFY;
	           end if;

     	      when S_WOTS_VRFY =>
     	          q.mode_select_l1 <= "01";
     	          q.wots.enable <= '1';
     	          if d.wots.done = '1' then
     	              v.state := S_LTREE;
     	          end if;

     	      when S_LTREE =>
     	          q.mode_select_l1 <= "11";
     	          q.l_tree.enable <= '1';
     	          if d.l_tree.done = '1' then
     	              v.bram_state_b := B_ROOT; 
     	              v.state := S_COMP_ROOT;
     	          end if;

     	      when S_COMP_ROOT =>
     	          q.mode_select_l1 <= "00";
     	          compute_root.enable <= '1';
     	          if modules_root_q.done = '1' then
     	              q.done <= '1';
     	              if modules_root_q.root = d.bram.b.dout then 
     	                  q.valid <= '1';
     	              end if;
     	              v.state := S_IDLE;
     	          end if;
	    end case;
     	r_in <= v;
    end process;

    bram_mux_b : process(r.bram_state_b)
    begin
        -- BLINDAJE CONTRA 'U' y 'X':
        q.bram.b.addr <= (others => '0'); 
        case r.bram_state_b is
            when B_INDEX => q.bram.b.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG, BRAM_ADDR_SIZE));
            when B_PUB_SEED => q.bram.b.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG+2, BRAM_ADDR_SIZE));
            when B_ROOT => q.bram.b.addr <= std_logic_vector(to_unsigned(BRAM_XMSS_SIG+3, BRAM_ADDR_SIZE));
        end case;
    end process;

    sequential : process(clk)
	begin
	   if rising_edge(clk) then
	    if reset = '1' then
	       r.state <= S_IDLE;
           -- EL FIX CRÍTICO: Inicializar todo a un valor seguro
           r.index <= (others => '0');
           r.bram_state_b <= B_INDEX;
	    else
		   r <= r_in;
        end if;
       end if;
    end process;
end Behavioral;