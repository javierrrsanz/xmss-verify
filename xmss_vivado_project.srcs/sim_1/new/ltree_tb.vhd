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

    -- Interfaces de los Módulos
    signal wots_in   : wots_input_type;
    signal wots_out  : wots_output_type;
    signal ltree_in  : xmss_l_tree_input_type;
    signal ltree_out : xmss_l_tree_output_type;
    signal thash_in  : xmss_thash_h_input_type;
    signal thash_out : xmss_thash_h_output_type;
    signal hash_in   : hash_subsystem_input_type;
    signal hash_out  : hash_subsystem_output_type;

    -- Emulador de BRAM
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    signal bram_memory : ram_type := (others => (others => '0'));

    -- Multiplexor de Bus
    signal active_module : integer := 0; -- 0: WOTS, 1: LTREE

    -- Semilla Pública Constante (NIST Vector)
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";

    -- Función auxiliar para imprimir el Hash en consola
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

    -- =====================================================================
    -- INSTANCIAS DE LOS MÓDULOS (Device Under Test)
    -- =====================================================================
    wots_inst : entity work.wots
        port map(clk => clk, reset => reset, d => wots_in, q => wots_out);

    ltree_inst : entity work.l_tree
        port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);

    thash_inst : entity work.thash_h
        port map(clk => clk, reset => reset, d => thash_in, q => thash_out);

    hash_inst : entity work.hash_core_collection
        port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    -- =====================================================================
    -- CABLEADO Y MULTIPLEXORES LÓGICOS
    -- =====================================================================
    
    -- 1. THASH <-> L-TREE (L-Tree controla al THASH)
    thash_in.module_input <= ltree_out.thash;
    thash_in.pub_seed     <= PUB_SEED;
    ltree_in.thash        <= thash_out.module_output;

    -- 2. HASH BUS MUX (WOTS o THASH hablan con el Hash Core dependiendo del ciclo)
    hash_in       <= wots_out.hash when active_module = 0 else thash_out.hash;
    wots_in.hash  <= hash_out;
    thash_in.hash <= hash_out;

    -- 3. BRAM MUX & EMULADOR
    process(clk)
        variable addr_a, addr_b : integer;
        variable en_a, wen_a, en_b, wen_b : std_logic;
        variable din_a, din_b : std_logic_vector(255 downto 0);
    begin
        if rising_edge(clk) then
            -- Mux de señales según quién tenga el control
            if active_module = 0 then
                addr_a := to_integer(unsigned(wots_out.bram.a.addr));
                en_a   := wots_out.bram.a.en;
                wen_a  := wots_out.bram.a.wen;
                din_a  := wots_out.bram.a.din;

                addr_b := to_integer(unsigned(wots_out.bram.b.addr));
                en_b   := wots_out.bram.b.en;
                wen_b  := wots_out.bram.b.wen;
                din_b  := wots_out.bram.b.din;
            else
                addr_a := to_integer(unsigned(ltree_out.bram.a.addr));
                en_a   := ltree_out.bram.a.en;
                wen_a  := ltree_out.bram.a.wen;
                din_a  := ltree_out.bram.a.din;

                addr_b := to_integer(unsigned(ltree_out.bram.b.addr));
                en_b   := ltree_out.bram.b.en;
                wen_b  := ltree_out.bram.b.wen;
                din_b  := ltree_out.bram.b.din;
            end if;

            -- Escritura/Lectura Puerto A
            if en_a = '1' then
                if wen_a = '1' then
                    bram_memory(addr_a) <= din_a;
                end if;
                ltree_in.bram.a.dout <= bram_memory(addr_a);
            end if;

            -- Escritura/Lectura Puerto B
            if en_b = '1' then
                if wen_b = '1' then
                    bram_memory(addr_b) <= din_b;
                end if;
                wots_in.bram_b.dout <= bram_memory(addr_b);
                ltree_in.bram.b.dout <= bram_memory(addr_b);
            end if;
        end if;
    end process;

    -- =====================================================================
    -- GENERADOR DE RELOJ
    -- =====================================================================
    process begin
        clk <= '1'; wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

    -- =====================================================================
    -- SECUENCIA PRINCIPAL DE PRUEBAS
    -- =====================================================================
    process
    begin
        -- Estado Seguro Inicial
        active_module <= 0;
        wots_in.module_input.enable <= '0';
        ltree_in.module_input.enable <= '0';
        reset <= '1';
        wait for 4 * clk_period;
        reset <= '0';
        wait for 4 * clk_period;

        -- ==========================================================
        -- FASE 1: LLENAR LA BRAM CON CLAVES WOTS PERFECTAS
        -- ==========================================================
        report "=== [FASE 1] GENERANDO WOTS PUBLIC KEY EN BRAM ===" severity note;
        active_module <= 0;
        wots_in.module_input.mode <= "00";
        wots_in.module_input.seed <= x"a344f01778bb4aca2d1406c8821017fbd029aa42803a835c362396778c678dfa";
        wots_in.pub_seed <= PUB_SEED;
        wots_in.module_input.address_4 <= x"00000000";

        wots_in.module_input.enable <= '1';
        wait for clk_period;
        wots_in.module_input.enable <= '0';

        loop
            wait until rising_edge(clk);
            exit when wots_out.module_output.done = '1';
        end loop;
        report "    [OK] WOTS PK Generada y guardada en memoria BRAM." severity note;
        wait for 10 * clk_period;

        -- ==========================================================
        -- FASE 2: COMPRIMIR TODO CON L-TREE + THASH
        -- ==========================================================
        report "=== [FASE 2] INICIANDO L-TREE (COMPRESION DE 67 BLOQUES) ===" severity note;
        active_module <= 1; -- MUX: Le pasamos el control de memoria y Hash al L-Tree
        ltree_in.module_input.address_4 <= x"00000000";

        ltree_in.module_input.enable <= '1';
        wait for clk_period;
        ltree_in.module_input.enable <= '0';

        loop
            wait until rising_edge(clk);
            exit when ltree_out.module_output.done = '1';
        end loop;
        report "    [OK] Compresion finalizada con exito." severity note;

        -- ==========================================================
        -- RESULTADO DE LA VERIFICACION MATEMATICA
        -- ==========================================================
        report "=======================================================" severity note;
        report "LEAF NODE RESULTANTE: " & to_hex_string(ltree_out.module_output.leaf_node) severity note;
        report "=======================================================" severity note;

        wait;
    end process;
end architecture;