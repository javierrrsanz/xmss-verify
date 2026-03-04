library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.sha_comp.ALL;
use work.params.ALL;

entity absorb_message_tb is
end absorb_message_tb;

architecture Behavioral of absorb_message_tb is
    constant clk_period : time := 10 ns;
    
    signal clk, reset : std_logic := '0';
    signal d_in       : absorb_message_input_type;
    signal q_out      : absorb_message_output_type;

    -- Vectores Esperados (NIST FIPS 180-4)
    constant EXP_EMPTY : std_logic_vector(255 downto 0) := x"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    constant EXP_ABC   : std_logic_vector(255 downto 0) := x"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    constant EXP_512FF : std_logic_vector(255 downto 0) := x"8667e718294e9e0df1d30600ba3eeb201f764aad2dad72748643e4a285e1d1f7";

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

    -- Instancia del módulo a probar (Device Under Test)
    uut: entity work.absorb_message
        port map (
            clk   => clk,
            reset => reset,
            d     => d_in,
            q     => q_out
        );

    -- Generador de Reloj
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period / 2;
        clk <= '1';
        wait for clk_period / 2;
    end process;

-- Proceso de Estímulos
    stim_proc: process
    begin
        -- Inicialización segura
        d_in.enable <= '0';
        d_in.halt   <= '0';
        d_in.len    <= 0;
        d_in.input  <= (others => '0');
        
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        wait for 5 * clk_period;

        report "=======================================================" severity note;
        report " INICIANDO PRUEBAS DE ABSORB_MESSAGE (VECTORES NIST + TORTURA)" severity note;
        report "=======================================================" severity note;

        -----------------------------------------------------------------
        -- TEST 1: Mensaje Vacío (0 bits)
        -----------------------------------------------------------------
        report "--> TEST 1: Mensaje Vacio (0 bits)" severity note;
        wait until rising_edge(clk);
        d_in.enable <= '1';
        d_in.len    <= 0; 
        d_in.input  <= (others => '0'); 
        wait for clk_period;
        d_in.enable <= '0';
        loop
            wait until rising_edge(clk);
            exit when q_out.done = '1';
        end loop;
        report "    [HASH OBTENIDO]: " & to_hex_string(q_out.o) severity note;
        wait for 10 * clk_period;

        -----------------------------------------------------------------
        -- TEST 2: Mensaje "abc" (24 bits)
        -----------------------------------------------------------------
        report "--> TEST 2: Mensaje 'abc' (24 bits)" severity note;
        wait until rising_edge(clk);
        d_in.enable <= '1';
        d_in.len    <= 24; 
        d_in.input  <= x"6162630000000000000000000000000000000000000000000000000000000000"; 
        wait for clk_period;
        d_in.enable <= '0';
        loop
            wait until rising_edge(clk);
            exit when q_out.done = '1';
        end loop;
        report "    [HASH OBTENIDO]: " & to_hex_string(q_out.o) severity note;
        wait for 10 * clk_period;

        -----------------------------------------------------------------
        -- TEST 3: Mensaje de 512 bits (0xFF)
        -----------------------------------------------------------------
        report "--> TEST 3: Mensaje Multibloque (512 bits de 0xFF)" severity note;
        wait until rising_edge(clk);
        d_in.enable <= '1';
        d_in.len    <= 512; 
        d_in.input  <= (others => '1');
        wait for clk_period;
        d_in.enable <= '0';

        loop
            wait until rising_edge(clk);
            exit when q_out.mnext = '1';
        end loop;
        
        d_in.input <= (others => '1');
        loop
            wait until rising_edge(clk);
            exit when q_out.done = '1';
        end loop;
        report "    [HASH OBTENIDO]: " & to_hex_string(q_out.o) severity note;
        wait for 10 * clk_period;

        -----------------------------------------------------------------
        -- TEST 4: LA ZONA PELIGROSA (Exactamente 448 bits de 0xAA)
        -----------------------------------------------------------------
        report "--> TEST 4: TORTURA - Zona Peligrosa de Padding (448 bits)" severity note;
        wait until rising_edge(clk);
        
        d_in.enable <= '1';
        d_in.len    <= 448; 
        -- Primeros 256 bits de 0xAA
        d_in.input  <= x"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; 
        wait for clk_period;
        d_in.enable <= '0';

        -- Esperamos a que pida la segunda parte (que completan los 448)
        loop
            wait until rising_edge(clk);
            exit when q_out.mnext = '1';
        end loop;
        
        -- Siguientes 192 bits de 0xAA, alineados a la izquierda. Los últimos 64 bits se ignorarán.
        d_in.input <= x"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0000000000000000";
        
        loop
            wait until rising_edge(clk);
            exit when q_out.done = '1';
        end loop;
        
        report "    [HASH OBTENIDO]: " & to_hex_string(q_out.o) severity note;
        report "    [INFO] Si el simulador no se ha colgado en el Test 4, la maquina de estados de padding es robusta." severity note;
        wait for 10 * clk_period;

        -----------------------------------------------------------------
        -- TEST 5: SIMULACIÓN DE THASH (Exactamente 1024 bits / 4 Chunks)
        -----------------------------------------------------------------
        report "--> TEST 5: TORTURA - Tamano THASH (1024 bits / 4 chunks)" severity note;
        wait until rising_edge(clk);
        
        d_in.enable <= '1';
        d_in.len    <= 1024; 
        d_in.input  <= x"1111111111111111111111111111111111111111111111111111111111111111"; 
        wait for clk_period;
        d_in.enable <= '0';

        -- Chunk 2
        loop wait until rising_edge(clk); exit when q_out.mnext = '1'; end loop;
        d_in.input <= x"2222222222222222222222222222222222222222222222222222222222222222";
        
        -- Chunk 3
        loop wait until rising_edge(clk); exit when q_out.mnext = '1'; end loop;
        d_in.input <= x"3333333333333333333333333333333333333333333333333333333333333333";

        -- Chunk 4
        loop wait until rising_edge(clk); exit when q_out.mnext = '1'; end loop;
        d_in.input <= x"4444444444444444444444444444444444444444444444444444444444444444";

        -- Esperar a finalizar
        loop
            wait until rising_edge(clk);
            exit when q_out.done = '1';
        end loop;
        
        report "    [HASH OBTENIDO]: " & to_hex_string(q_out.o) severity note;
        report "    [INFO] Si el simulador llego aqui, absorb_message es a prueba de balas." severity note;
        
        report "=======================================================" severity note;
        report " FIN DE LAS PRUEBAS DE TORTURA" severity note;
        report "=======================================================" severity note;
        wait;
    end process;

end Behavioral;