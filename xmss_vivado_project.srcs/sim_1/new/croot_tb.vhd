library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;

entity croot_tb is
end croot_tb;

architecture Behavioral of croot_tb is
    constant clk_period : time := 5 ns;
    signal clk, reset : std_logic := '0';

    -- Interfaces de los Módulos
    signal croot_in   : xmss_compute_root_input_type;
    signal croot_out  : xmss_compute_root_output_type;
    signal thash_in   : xmss_thash_h_input_type;
    signal thash_out  : xmss_thash_h_output_type;
    signal hash_in    : hash_subsystem_input_type;
    signal hash_out   : hash_subsystem_output_type;

    -- Emulador de Memoria
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    signal bram_memory : ram_type := (others => (others => '0'));

    -- Semilla Pública Constante (NIST Vector)
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";

    -- Señales para emular el DMA
    signal mem_pending : std_logic := '0';
    signal mem_addr_lat : std_logic_vector(31 downto 0) := (others => '0');

    -- Función auxiliar para imprimir el Hash
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
    -- INSTANCIAS DE LOS MÓDULOS
    -- =====================================================================
    croot_inst : entity work.compute_root
        port map(clk => clk, reset => reset, d => croot_in, q => croot_out);

    thash_inst : entity work.thash_h
        port map(clk => clk, reset => reset, d => thash_in, q => thash_out);

    hash_inst : entity work.hash_core_collection
        port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    -- =====================================================================
    -- CABLEADO
    -- =====================================================================
    
    -- Compute_root <-> THASH
    thash_in.module_input <= croot_out.thash;
    thash_in.pub_seed     <= PUB_SEED;
    croot_in.thash        <= thash_out.module_output;

    -- THASH <-> Hash Core
    hash_in       <= thash_out.hash;
    thash_in.hash <= hash_out;

    -- =====================================================================
    -- EMULADOR DE MEMORIA EXTERNA (DMA OBI)
    -- =====================================================================
    croot_in.mem.gnt <= '1'; -- El bus siempre acepta peticiones

    process(clk)
        variable idx : integer;
    begin
        if rising_edge(clk) then
            croot_in.mem.valid <= '0';

            if mem_pending = '1' then
                -- La dirección viene en bytes. Dividimos por 32 (shift_right 5) para sacar el índice del array
                idx := to_integer(shift_right(unsigned(mem_addr_lat), 5));
                croot_in.mem.data <= bram_memory(idx);
                croot_in.mem.valid <= '1';
                mem_pending <= '0';
            end if;

            if croot_out.mem.req = '1' then
                mem_addr_lat <= croot_out.mem.addr;
                mem_pending <= '1';
            end if;
        end if;
    end process;

    -- =====================================================================
    -- GENERADOR DE RELOJ
    -- =====================================================================
    process begin
        clk <= '1';
        wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

    -- =====================================================================
    -- SECUENCIA DE PRUEBA
    -- =====================================================================
    process
    begin
        croot_in.enable <= '0';
        croot_in.leaf <= (others => '0');
        croot_in.leaf_idx <= 0;
        reset <= '1';
        wait for 4 * clk_period;
        reset <= '0';
        wait for 4 * clk_period;

        -- Rellenar la BRAM con una "Ruta de Autenticación" (Auth Path) ficticia de 10 niveles
        for i in 0 to tree_height - 1 loop
            -- Rellenamos con un patrón reconocible para simular los hashes de la firma
            bram_memory(BRAM_XMSS_SIG_AUTH + i) <= std_logic_vector(to_unsigned(i + 1, 256));
        end loop;

        report "=======================================================" severity note;
        report "=== INICIANDO PRUEBA DE COMPUTE_ROOT (10 NIVELES) ===" severity note;

        -- Inyectamos el Leaf Node 
        croot_in.leaf <= x"ac99903b040ab13c33f7ee1a1751c8d67737ab76bd700a9563ff58c611050da8";
        croot_in.leaf_idx <= 5; 

        -- Arrancamos
        croot_in.enable <= '1';
        wait for clk_period;
        croot_in.enable <= '0';

        -- Esperar a que calcule los 10 niveles
        loop
            wait until rising_edge(clk);
            exit when croot_out.done = '1';
        end loop;

        report "    [OK] Computo del arbol finalizado con exito." severity note;
        report "=======================================================" severity note;
        report "ROOT NODE CALCULADO: " & to_hex_string(croot_out.root) severity note;
        report "=======================================================" severity note;

        wait;
    end process;

end Behavioral;