library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;
use work.wots_comp.ALL;

entity verify_tb is
end verify_tb;

architecture Behavioral of verify_tb is
    constant clk_period : time := 5 ns;
    signal clk, reset : std_logic := '0';

    signal vrfy_in  : xmss_verify_input_type;
    signal vrfy_out : xmss_verify_output_type;
    signal hmsg_in  : hash_message_input_type;
    signal hmsg_out : hash_message_output_type;
    signal wots_in  : wots_input_type;
    signal wots_out : wots_output_type;
    signal ltree_in : xmss_l_tree_input_type;
    signal ltree_out: xmss_l_tree_output_type;
    signal thash_in : xmss_thash_h_input_type;
    signal thash_out: xmss_thash_h_output_type;
    signal hash_in  : hash_subsystem_input_type;
    signal hash_out : hash_subsystem_output_type;

    signal bram_dout_a_reg, bram_dout_b_reg : std_logic_vector(255 downto 0) := (others => '0');
    
    -- =====================================================================
    -- 1. DECLARACIONES ORDENADAS
    -- =====================================================================
    
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";

    -- PRIMERO: Declaramos el tipo de la memoria
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);

    -- SEGUNDO: Declaramos la función que devuelve ese tipo e inyectamos los datos
    impure function init_bram return ram_type is
        variable mem_var : ram_type := (others => (others => '0'));
    begin
        -- Firma Falsa
        mem_var(BRAM_XMSS_SIG) := (others => '0'); 
        mem_var(BRAM_XMSS_SIG + 1) := x"1111111111111111111111111111111111111111111111111111111111111111"; 
        mem_var(BRAM_XMSS_SIG + 2) := PUB_SEED; 
        
        -- !!! AQUI ESTA LA RAIZ REAL CALCULADA INYECTADA EN LA MEMORIA !!!
        mem_var(BRAM_XMSS_SIG + 3) := x"2dbe8ab5956fedcdfa4db12a2792414f02d18bcc483ed62f30dba45e8725df5e"; 
        
        mem_var(BRAM_MESSAGE) := x"3833653732376265633437323133363862663265306563666666303931333461";

        for i in 0 to 66 loop 
            mem_var(BRAM_XMSS_SIG_WOTS + i) := std_logic_vector(to_unsigned(i, 256)); 
        end loop;
        for i in 0 to 9 loop 
            mem_var(BRAM_XMSS_SIG_AUTH + i) := std_logic_vector(to_unsigned(i+100, 256)); 
        end loop;
        
        return mem_var;
    end function;

    -- TERCERO: Instanciamos la memoria llamando a la función
    signal bram_memory : ram_type := init_bram;

    signal tb_enable : std_logic := '0';

begin

    -- =====================================================================
    -- 2. CABLEADO SÍNCRONO ATÓMICO (Sin Múltiples Controladores)
    -- =====================================================================
    vrfy_in.enable <= tb_enable;
    vrfy_in.mlen <= 256;
    vrfy_in.wots <= wots_out.module_output;
    vrfy_in.l_tree <= ltree_out.module_output;
    vrfy_in.thash <= thash_out.module_output;
    vrfy_in.hash_message <= hmsg_out.module_output;
    vrfy_in.bram.a.dout <= bram_dout_a_reg;
    vrfy_in.bram.b.dout <= bram_dout_b_reg;

    process(vrfy_out, hash_out, bram_dout_b_reg) begin
        hmsg_in.module_input <= vrfy_out.hash_message;
        hmsg_in.hash <= hash_out;
        hmsg_in.bram.dout <= bram_dout_b_reg;
    end process;

    process(vrfy_out, hash_out, bram_dout_b_reg) begin
        wots_in.module_input <= vrfy_out.wots;
        wots_in.pub_seed <= PUB_SEED;
        wots_in.bram_b.dout <= bram_dout_b_reg;
        wots_in.hash <= hash_out;
    end process;

    process(vrfy_out, ltree_out, thash_out, hash_out, bram_dout_a_reg, bram_dout_b_reg) begin
        ltree_in.module_input <= vrfy_out.l_tree;
        ltree_in.bram.a.dout <= bram_dout_a_reg;
        ltree_in.bram.b.dout <= bram_dout_b_reg;
        ltree_in.thash <= thash_out.module_output;
        
        if vrfy_out.mode_select_l1 = "11" then
            thash_in.module_input <= ltree_out.thash;
        else
            thash_in.module_input <= vrfy_out.thash;
        end if;
        thash_in.pub_seed <= PUB_SEED;
        thash_in.hash <= hash_out;
    end process;

    hash_in <= hmsg_out.hash when vrfy_out.mode_select_l1 = "10" else 
               wots_out.hash when vrfy_out.mode_select_l1 = "01" else 
               thash_out.hash;

    -- =====================================================================
    -- 3. INSTANCIAS DE MÓDULOS
    -- =====================================================================
    uut : entity work.xmss_verify port map(clk => clk, reset => reset, d => vrfy_in, q => vrfy_out);
    hms: entity work.hash_message port map(clk => clk, reset => reset, d => hmsg_in, q => hmsg_out);
    wts: entity work.wots port map(clk => clk, reset => reset, d => wots_in, q => wots_out);
    ltr: entity work.l_tree port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);
    ths: entity work.thash_h port map(clk => clk, reset => reset, d => thash_in, q => thash_out);
    hco: entity work.hash_core_collection port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    process begin
        clk <= '1'; wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

    -- =====================================================================
    -- 4. MULTIPLEXOR DE BRAM
    -- =====================================================================
    process(clk)
        variable addr_a, addr_b : integer;
        variable wen_a, wen_b : std_logic;
        variable din_a, din_b : std_logic_vector(255 downto 0);
    begin
        if rising_edge(clk) then
            if vrfy_out.mode_select_l1 = "01" then
                addr_a := to_integer(unsigned(wots_out.bram.a.addr)); wen_a := wots_out.bram.a.wen; din_a := wots_out.bram.a.din;
                addr_b := to_integer(unsigned(wots_out.bram.b.addr)); wen_b := wots_out.bram.b.wen; din_b := wots_out.bram.b.din;
            elsif vrfy_out.mode_select_l1 = "11" then
                addr_a := to_integer(unsigned(ltree_out.bram.a.addr)); wen_a := ltree_out.bram.a.wen; din_a := ltree_out.bram.a.din;
                addr_b := to_integer(unsigned(ltree_out.bram.b.addr)); wen_b := ltree_out.bram.b.wen; din_b := ltree_out.bram.b.din;
            else
                addr_a := to_integer(unsigned(vrfy_out.bram.a.addr)); wen_a := vrfy_out.bram.a.wen; din_a := vrfy_out.bram.a.din;
                if vrfy_out.mode_select_l1 = "10" then
                    addr_b := to_integer(unsigned(hmsg_out.bram.addr)); wen_b := hmsg_out.bram.wen; din_b := hmsg_out.bram.din;
                else
                    addr_b := to_integer(unsigned(vrfy_out.bram.b.addr)); wen_b := vrfy_out.bram.b.wen; din_b := vrfy_out.bram.b.din;
                end if;
            end if;

            if wen_a = '1' then bram_memory(addr_a) <= din_a; end if;
            if wen_b = '1' then bram_memory(addr_b) <= din_b; end if;
            
            bram_dout_a_reg <= bram_memory(addr_a);
            bram_dout_b_reg <= bram_memory(addr_b);
        end if;
    end process;

    -- =========================================================
    -- 5. SECUENCIA PRINCIPAL DE ESTÍMULOS
    -- =========================================================
    process
    begin
        reset <= '1'; 
        wait for 50 ns; 
        wait until rising_edge(clk);
        reset <= '0'; 
        wait for 50 ns;
        
        report "=== ENCENDIENDO ACELERADOR: MODO VERIFICACION ===" severity note;
        
        wait until rising_edge(clk);
        tb_enable <= '1'; 
        wait until rising_edge(clk);
        tb_enable <= '0';

        wait until vrfy_out.done = '1';
        report "=== VERIFICACION FINALIZADA ===" severity note;
        
        if vrfy_out.valid = '1' then
            report "    [PASS] RESULTADO DE LA FIRMA: VALID = 1 (LA RAIZ COINCIDE)" severity note;
        else
            report "    [FAIL] RESULTADO DE LA FIRMA: VALID = 0" severity error;
            report "    >> ATENCION: Ve a las formas de onda, busca 'uut/modules_root_q.root' y pega el valor en la BRAM." severity note;
        end if;
        report "=======================================================" severity note;
        wait;
    end process;



end Behavioral;