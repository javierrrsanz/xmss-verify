library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;
use work.wots_comp.ALL;

entity ltree_tb is
end ltree_tb;

architecture Behavioral of ltree_tb is
    constant clk_period : time := 5 ns;
    signal clk, reset : std_logic := '0';

    signal wots_in   : wots_input_type;
    signal wots_out  : wots_output_type;
    signal ltree_in  : xmss_l_tree_input_type;
    signal ltree_out : xmss_l_tree_output_type;
    signal thash_in  : xmss_thash_h_input_type;
    signal thash_out : xmss_thash_h_output_type;
    signal hash_in   : hash_subsystem_input_type;
    signal hash_out  : hash_subsystem_output_type;

    -- Scratchpad para el L-Tree (donde asume que WOTS guardó los 67 bloques)
    type scratch_ram_type is array (0 to 127) of std_logic_vector(n*8-1 downto 0);
    signal scratch_mem : scratch_ram_type := (others => (others => '0'));

    signal active_module : integer := 1; -- Forzamos 1 para que solo mande L-Tree
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";

    function to_hex_string(sv : std_logic_vector) return string is
        constant hex_chars : string(1 to 16) := "0123456789abcdef";
        variable result : string(1 to sv'length/4);
        variable nibble : integer;
        variable temp_sv : std_logic_vector(sv'length-1 downto 0) := sv;
    begin
        if sv'length mod 4 /= 0 then return "LenError"; end if;
        for i in 0 to (sv'length/4)-1 loop
            nibble := to_integer(unsigned(temp_sv(temp_sv'length-1 downto temp_sv'length-4)));
            result(i+1) := hex_chars(nibble+1);
            if temp_sv'length > 4 then temp_sv := temp_sv(temp_sv'length-5 downto 0) & "0000"; end if;
        end loop;
        return result;
    end function;

begin

    wots_inst : entity work.wots port map(clk => clk, reset => reset, d => wots_in, q => wots_out);
    ltree_inst : entity work.l_tree port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);
    thash_inst : entity work.thash_h port map(clk => clk, reset => reset, d => thash_in, q => thash_out);
    hash_inst : entity work.hash_core_collection port map(clk => clk, reset => reset, d => hash_in, q => hash_out);
    
    -- Cableado Lógico
    thash_in.module_input <= ltree_out.thash;
    thash_in.pub_seed     <= PUB_SEED;
    ltree_in.thash        <= thash_out.module_output;
    hash_in               <= thash_out.hash;
    thash_in.hash         <= hash_out;

    -- Conexiones inactivas (evita Warnings)
    wots_in.sig_mem <= mem_read_rsp_zero;
    wots_in.hash <= hash_out;

    -- BRAM MUX (Solo L-Tree)
    process(clk)
        variable addr_a, addr_b : integer;
    begin
        if rising_edge(clk) then
            addr_a := to_integer(unsigned(ltree_out.bram.a.addr));
            addr_b := to_integer(unsigned(ltree_out.bram.b.addr));
            
            if ltree_out.bram.a.en = '1' then
                if ltree_out.bram.a.wen = '1' then scratch_mem(addr_a) <= ltree_out.bram.a.din; end if;
                ltree_in.bram.a.dout <= scratch_mem(addr_a);
            end if;

            if ltree_out.bram.b.en = '1' then
                if ltree_out.bram.b.wen = '1' then scratch_mem(addr_b) <= ltree_out.bram.b.din; end if;
                ltree_in.bram.b.dout <= scratch_mem(addr_b);
            end if;
        end if;
    end process;

    process begin clk <= '1'; wait for clk_period / 2; clk <= '0'; wait for clk_period / 2; end process;

    process
    begin
        -- Estado Seguro Inicial
        ltree_in.module_input.enable <= '0';
        wots_in.module_input.enable <= '0';
        reset <= '1';
        wait for 4 * clk_period;
        reset <= '0';
        wait for 4 * clk_period;

        report "=== [FASE 2] INICIANDO L-TREE (COMPRESION DE 67 BLOQUES) ===" severity note;
        ltree_in.module_input.address_4 <= x"00000000";
        ltree_in.module_input.enable <= '1';
        wait for clk_period;
        ltree_in.module_input.enable <= '0';

        loop
            wait until rising_edge(clk);
            exit when ltree_out.module_output.done = '1';
        end loop;
        
        report "    [OK] Compresion finalizada con exito." severity note;
        report "=======================================================" severity note;
        report "LEAF NODE RESULTANTE: " & to_hex_string(ltree_out.module_output.leaf_node) severity note;
        report "=======================================================" severity note;

        wait;
    end process;
end architecture;