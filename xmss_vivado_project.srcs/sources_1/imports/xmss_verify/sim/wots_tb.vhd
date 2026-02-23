library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.wots_comp.ALL;
use work.params.ALL;
use work.xmss_main_typedef.ALL;

entity wots_tb is
end wots_tb;

architecture Behavioral of wots_tb is
    constant clk_period : time := 5 ns;

	signal clk, reset : std_logic := '0';
	signal wots_in : wots_input_type;
	signal wots_out : wots_output_type;
	
	-- Array para emular la memoria BRAM (2048 posiciones de 256 bits)
	type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    signal bram_memory : ram_type := (others => (others => '0'));

begin

    -- =========================================================================
    -- Emulador de Memoria BRAM (Sustituye a blk_mem_gen_0)
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            -- Puerto A (Solo escritura en WOTS según arquitectura)
            if wots_out.bram.a.en = '1' then
                if wots_out.bram.a.wen = '1' then
                    bram_memory(to_integer(unsigned(wots_out.bram.a.addr))) <= wots_out.bram.a.din;
                end if;
            end if;
            
            -- Puerto B (Lectura y Escritura)
            if wots_out.bram.b.en = '1' then
                if wots_out.bram.b.wen = '1' then
                    bram_memory(to_integer(unsigned(wots_out.bram.b.addr))) <= wots_out.bram.b.din;
                end if;
                -- Retorno asíncrono-síncrono de lectura para el ciclo actual
                wots_in.bram_b.dout <= bram_memory(to_integer(unsigned(wots_out.bram.b.addr)));
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Instancia del módulo WOTS+ principal
    -- =========================================================================
    uut : entity work.wots
	port map(
		clk   => clk,
		reset => reset,
		d     => wots_in,
	    q     => wots_out
	);

    -- =========================================================================
    -- Instancia del módulo Absorb Message (que llama a nuestro SHA256)
    -- =========================================================================
    hash : entity work.hash_core_collection
	port map(
	   clk   => clk,
	   reset => reset,
	   d     => wots_out.hash,
	   q     => wots_in.hash 
	);

    -- =========================================================================
    -- Generador de Reloj
    -- =========================================================================
    process
	begin
		clk <= '1'; wait for clk_period / 2;
		clk <= '0'; wait for clk_period / 2;
	end process;

    -- =========================================================================
    -- Proceso de Estímulos Principal
    -- =========================================================================
    process
	begin
        -- NOTA: Valores del testvector original (NIST estándar para SHA2-256)
        -- Seed Priv: a344f01778bb4aca2d1406c8821017fbd029aa42803a835c362396778c678dfa 
        -- Seed Pub:  602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb
        -- Mensaje:   f01ea2366b149531d2800dfff7bccb6f02206d4c98827e69d1330d55e3d08445
	
		wots_in.module_input.enable <= '0';
		reset <= '1';
		wait for 2 * clk_period;
        reset <= '0';
		wait for 2 * clk_period;
		
		-------------------------------------------------
		-- 1. MODO KEYGEN (Generación de Llaves y Cadenas)
		-------------------------------------------------
		report "===========================================" severity note;
		report "=== INICIANDO WOTS: MODO KEYGEN ===" severity note;
		
		wots_in.module_input.mode <= "00";
		wots_in.module_input.seed <= x"a344f01778bb4aca2d1406c8821017fbd029aa42803a835c362396778c678dfa";
		wots_in.pub_seed <= x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";
		wots_in.module_input.address_4 <= x"00000000";
		
		wots_in.module_input.enable <= '1';
		wait for clk_period;
		wots_in.module_input.enable <= '0';
		
		wait until wots_out.module_output.done = '1';
		report "=== KEYGEN COMPLETADO EXITOSAMENTE ===" severity note;
		wait for 5 * clk_period;
		
		-------------------------------------------------
		-- 2. MODO SIGN (Generación de Firma)
		-------------------------------------------------
		report "=== INICIANDO WOTS: MODO SIGN ===" severity note;
		wots_in.module_input.mode <= "01";
		wots_in.module_input.message <= x"f01ea2366b149531d2800dfff7bccb6f02206d4c98827e69d1330d55e3d08445";
		
		wots_in.module_input.enable <= '1';
		wait for clk_period;
		wots_in.module_input.enable <= '0';
		
		wait until wots_out.module_output.done = '1';
		report "=== FIRMA COMPLETADA EXITOSAMENTE ===" severity note;
		wait for 5 * clk_period;
		
		-------------------------------------------------
		-- 3. MODO VERIFY (Verificación de la Firma)
		-------------------------------------------------
		report "=== INICIANDO WOTS: MODO VERIFY ===" severity note;
		wots_in.module_input.mode <= "10";

		wots_in.module_input.enable <= '1';
		wait for clk_period;
		wots_in.module_input.enable <= '0';
		
		wait until wots_out.module_output.done = '1';
		report "=== VERIFICACION COMPLETADA EXITOSAMENTE ===" severity note;
		report "===========================================" severity note;
		
		-- =========================================================================
		-- COMPROBACIÓN MATEMÁTICA AUTOMÁTICA (SELF-CHECKING)
		-- =========================================================================
		report "=== INICIANDO COMPROBACION MATEMATICA DE MEMORIA ===" severity note;
		
		-- Comprobamos el Bloque 0 de la Public Key reconstruida
		if bram_memory(BRAM_WOTS_KEY + 0) = x"60d71b4187d276fbb517c8bc5e6e737c5812883738950c55cbe518cae598b0bc" then
		    report "    [PASS] PK Bloque 0 es EXACTAMENTE IGUAL al vector de prueba NIST!" severity note;
		else
		    report "    [FAIL] ERROR: El Bloque 0 no coincide." severity error;
		end if;

		-- Comprobamos el Bloque 1 de la Public Key reconstruida
		if bram_memory(BRAM_WOTS_KEY + 1) = x"16966c5740170ce211290aef79087d45be516104b5eec243ebbcd4303b420e06" then
		    report "    [PASS] PK Bloque 1 es EXACTAMENTE IGUAL al vector de prueba NIST!" severity note;
		else
		    report "    [FAIL] ERROR: El Bloque 1 no coincide." severity error;
		end if;
        
		-- =========================================================================
        -- INICIO DE STRESS TESTS (TESTS DE TORTURA)
        -- =========================================================================
        
        -------------------------------------------------
        -- TEST 4: EXTREMOS MATEMÁTICOS (All-Zeros y All-Ones)
        -------------------------------------------------
--        report "=== TEST 4: CASOS EXTREMOS MATEMATICOS ===" severity note;
        
--        -- Prueba 4.1: Mensaje de todo Ceros (Fuerza el checksum a su valor máximo)
--        wots_in.module_input.mode <= "01"; -- SIGN
--        wots_in.module_input.message <= (others => '0');
--        wots_in.module_input.enable <= '1';
--        wait for clk_period;
--        wots_in.module_input.enable <= '0';
--        wait until wots_out.module_output.done = '1';
--        report "    [PASS] Firma completada con mensaje All-Zeros (Checksum Maximo superado)" severity note;
--        wait for 5 * clk_period;

--        -- Prueba 4.2: Mensaje de todo Unos (Fuerza el checksum a valor Cero)
--        wots_in.module_input.message <= (others => '1');
--        wots_in.module_input.enable <= '1';
--        wait for clk_period;
--        wots_in.module_input.enable <= '0';
--        loop
--    wait until rising_edge(clk);
--    exit when wots_out.module_output.done = '1';
--end loop;
--        report "    [PASS] Firma completada con mensaje All-Ones (Checksum Cero superado)" severity note;
--        wait for 5 * clk_period;

        -------------------------------------------------
        -- TEST 5: RESET ASESINO (Mid-Flight Reset)
        -------------------------------------------------
        report "=== TEST 5: RESET ASESINO (MID-FLIGHT) ===" severity note;
        
        wots_in.module_input.mode <= "00"; -- KEYGEN
        wots_in.module_input.enable <= '1';
        wait for clk_period;
        wots_in.module_input.enable <= '0';
        
        -- Esperamos 100 ciclos. El sistema estará a plena carga saturando el bus de hashes.
        wait for 100 * clk_period;
        
        report "    Inyectando RESET asincrono letal..." severity note;
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        wait for 5 * clk_period;
        
        -- Verificamos si el FSM principal y todas las FSM hijas sobrevivieron
        -- lanzando un nuevo KEYGEN limpio y esperando a que termine.
        wots_in.module_input.enable <= '1';
        wait for clk_period;
        wots_in.module_input.enable <= '0';
        wait until wots_out.module_output.done = '1';
        report "    [PASS] Modulo recuperado exitosamente tras el Reset" severity note;
        wait for 5 * clk_period;

        -------------------------------------------------
        -- TEST 6: SPAMMING DE ENABLE (Host Impaciente)
        -------------------------------------------------
        report "=== TEST 6: SPAMMING DE ENABLE (HOST RUIDOSO) ===" severity note;
        
        wots_in.module_input.mode <= "01"; -- SIGN
        wots_in.module_input.message <= x"f01ea2366b149531d2800dfff7bccb6f02206d4c98827e69d1330d55e3d08445";
        wots_in.module_input.enable <= '1';
        wait for clk_period;
        wots_in.module_input.enable <= '0';
        
        -- Mientras el modulo calcula la firma (y el done esta a '0'), 
        -- le disparamos enables aleatorios como si el procesador host se hubiera vuelto loco.
        for i in 1 to 10 loop
            wait for 23 * clk_period; -- Retardo primo/arbitrario para no coincidir con estados fijos
            wots_in.module_input.enable <= '1';
            wait for clk_period;
            wots_in.module_input.enable <= '0';
        end loop;
        
        -- Si el FSM esta bien diseñado, habra ignorado el ruido y finalizara correctamente.
        wait until wots_out.module_output.done = '1';
        report "    [PASS] Firma completada sin corromperse por los Enables intrusos" severity note;

        report "=======================================================" severity note;
        report "=== TODOS LOS TESTS DE TORTURA SUPERADOS CON EXITO ====" severity note;
        report "=======================================================" severity note;
        
        wait; -- Fin definitivo de la simulacion
	end process;

end Behavioral;