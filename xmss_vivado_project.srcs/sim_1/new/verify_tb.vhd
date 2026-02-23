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

    -- Señales del Top Level Verifier
    signal vrfy_in  : xmss_verify_input_type;
    signal vrfy_out : xmss_verify_output_type;

    -- Señales de los Submódulos
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

    -- Emulador de BRAM (Cargada con la firma falsa)
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    signal bram_memory : ram_type := (others => (others => '0'));

    signal mode : unsigned(1 downto 0);

    -- Semilla Pública
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";

begin

    -- =====================================================================
    -- 1. INSTANCIAS DE TODOS LOS MÓDULOS (TU CHIP COMPLETO)
    -- =====================================================================
    uut : entity work.xmss_verify
        port map(clk => clk, reset => reset, d => vrfy_in, q => vrfy_out);

    hash_msg_inst : entity work.hash_message
        port map(clk => clk, reset => reset, d => hmsg_in, q => hmsg_out);

    wots_inst : entity work.wots
        port map(clk => clk, reset => reset, d => wots_in, q => wots_out);

    ltree_inst : entity work.l_tree
        port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);

    thash_inst : entity work.thash_h
        port map(clk => clk, reset => reset, d => thash_in, q => thash_out);

    hash_core_inst : entity work.hash_core_collection
        port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    -- =====================================================================
    -- 2. CABLEADO DE CONTROL DE SUBMÓDULOS
    -- =====================================================================
    hmsg_in.module_input  <= vrfy_out.hash_message;
    vrfy_in.hash_message  <= hmsg_out.module_output;

    wots_in.module_input  <= vrfy_out.wots;
    vrfy_in.wots          <= wots_out.module_output;
    wots_in.pub_seed      <= PUB_SEED;

    ltree_in.module_input <= vrfy_out.l_tree;
    vrfy_in.l_tree        <= ltree_out.module_output;

    -- THASH lo usa Compute_Root (a través de vrfy_out) y L-Tree
    thash_in.module_input <= ltree_out.thash when mode = "11" else vrfy_out.thash;
    thash_in.pub_seed     <= PUB_SEED;
    vrfy_in.thash         <= thash_out.module_output;
    ltree_in.thash        <= thash_out.module_output;

    mode <= vrfy_out.mode_select_l1;

    -- =====================================================================
    -- 3. MUX DEL BUS DE HASH SHA-256
    -- =====================================================================
    hash_in <= hmsg_out.hash when mode = "10" else 
               wots_out.hash when mode = "01" else 
               thash_out.hash;

    hmsg_in.hash  <= hash_out;
    wots_in.hash  <= hash_out;
    thash_in.hash <= hash_out;

    -- =====================================================================
    -- 4. MUX DE LA MEMORIA BRAM (VERSIÓN VHDL-93 COMPATIBLE)
    -- =====================================================================
    process(clk)
        variable addr_a, addr_b : integer;
        variable en_a, wen_a, en_b, wen_b : std_logic;
        variable din_a, din_b : std_logic_vector(255 downto 0);
    begin
        if rising_edge(clk) then
            -- === EVALUACIÓN DEL PUERTO A ===
            if mode = "00" then
                en_a   := vrfy_out.bram.a.en;
                wen_a  := vrfy_out.bram.a.wen;
                din_a  := vrfy_out.bram.a.din;
                addr_a := to_integer(unsigned(vrfy_out.bram.a.addr));
            elsif mode = "01" then
                en_a   := wots_out.bram.a.en;
                wen_a  := wots_out.bram.a.wen;
                din_a  := wots_out.bram.a.din;
                addr_a := to_integer(unsigned(wots_out.bram.a.addr));
            elsif mode = "11" then
                en_a   := ltree_out.bram.a.en;
                wen_a  := ltree_out.bram.a.wen;
                din_a  := ltree_out.bram.a.din;
                addr_a := to_integer(unsigned(ltree_out.bram.a.addr));
            else
                en_a   := '0';
                wen_a  := '0';
                din_a  := (others => '0');
                addr_a := 0;
            end if;

            if en_a = '1' then
                if wen_a = '1' then
                    bram_memory(addr_a) <= din_a;
                end if;
                vrfy_in.bram.a.dout <= bram_memory(addr_a);
                wots_in.bram_b.dout <= bram_memory(addr_a); -- WOTS lee del addr_a a veces
                ltree_in.bram.a.dout <= bram_memory(addr_a);
            end if;

            -- === EVALUACIÓN DEL PUERTO B ===
            if mode = "00" then
                en_b   := vrfy_out.bram.b.en;
                wen_b  := vrfy_out.bram.b.wen;
                din_b  := vrfy_out.bram.b.din;
                addr_b := to_integer(unsigned(vrfy_out.bram.b.addr));
            elsif mode = "10" then
                en_b   := hmsg_out.bram.en;
                wen_b  := hmsg_out.bram.wen;
                din_b  := hmsg_out.bram.din;
                addr_b := to_integer(unsigned(hmsg_out.bram.addr));
            elsif mode = "01" then
                en_b   := wots_out.bram.b.en;
                wen_b  := wots_out.bram.b.wen;
                din_b  := wots_out.bram.b.din;
                addr_b := to_integer(unsigned(wots_out.bram.b.addr));
            elsif mode = "11" then
                en_b   := ltree_out.bram.b.en;
                wen_b  := ltree_out.bram.b.wen;
                din_b  := ltree_out.bram.b.din;
                addr_b := to_integer(unsigned(ltree_out.bram.b.addr));
            else
                en_b   := '0';
                wen_b  := '0';
                din_b  := (others => '0');
                addr_b := 0;
            end if;

            if en_b = '1' then
                if wen_b = '1' then
                    bram_memory(addr_b) <= din_b;
                end if;
                vrfy_in.bram.b.dout <= bram_memory(addr_b);
                hmsg_in.bram.dout   <= bram_memory(addr_b);
                wots_in.bram_b.dout <= bram_memory(addr_b);
                ltree_in.bram.b.dout <= bram_memory(addr_b);
            end if;
        end if;
    end process;

    -- =====================================================================
    -- 5. RELOJ
    -- =====================================================================
    process begin
        clk <= '1'; wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

    -- =====================================================================
    -- 6. SECUENCIA MAESTRA
    -- =====================================================================
    process
    begin
        vrfy_in.enable <= '0';
        vrfy_in.mlen <= 256; -- 32 bytes de mensaje
        reset <= '1';
        wait for 10 * clk_period;
        reset <= '0';
        wait for 10 * clk_period;

        -- CARGAMOS LA BRAM CON UNA "FIRMA" FALSA
        -- Índice de firma (0)
        bram_memory(BRAM_XMSS_SIG) <= (others => '0'); 
        -- R (Aleatoriedad)
        bram_memory(BRAM_XMSS_SIG + 1) <= x"1111111111111111111111111111111111111111111111111111111111111111"; 
        -- Pub Seed
        bram_memory(BRAM_XMSS_SIG + 2) <= PUB_SEED; 
        
        -- !!! AQUÍ PONDREMOS LA RAÍZ CORRECTA DESPUÉS DE LA PRIMERA EJECUCIÓN !!!
        bram_memory(BRAM_XMSS_SIG + 3) <= x"0000000000000000000000000000000000000000000000000000000000000000"; 
        
        -- Mensaje
        bram_memory(BRAM_MESSAGE) <= x"3833653732376265633437323133363862663265306563666666303931333461";

        -- WOTS Signature (67 bloques de basura determinista)
        for i in 0 to 66 loop
            bram_memory(BRAM_XMSS_SIG_WOTS + i) <= std_logic_vector(to_unsigned(i, 256));
        end loop;

        -- Auth Path (10 bloques de basura determinista)
        for i in 0 to tree_height - 1 loop
            bram_memory(BRAM_XMSS_SIG_AUTH + i) <= std_logic_vector(to_unsigned(i+100, 256));
        end loop;

        report "=======================================================" severity note;
        report "=== ENCENDIENDO ACELERADOR: MODO VERIFICAR FIRMA ===" severity note;
        
        vrfy_in.enable <= '1';
        wait for clk_period;
        vrfy_in.enable <= '0';

        loop
            wait until rising_edge(clk);
            exit when vrfy_out.done = '1';
        end loop;

        report "=== VERIFICACION FINALIZADA ===" severity note;
        
        if vrfy_out.valid = '1' then
            report "    [PASS] RESULTADO DE LA FIRMA: VALID = 1" severity note;
        else
            report "    [FAIL] RESULTADO DE LA FIRMA: VALID = 0" severity error;
            report "    >> ATENCION: Copia la raiz calculada del visualizador de ondas y ponla en la BRAM." severity note;
        end if;
        report "=======================================================" severity note;

        wait;
    end process;

end Behavioral;