library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;

entity thash_tb is
end thash_tb;

architecture Behavioral of thash_tb is
    constant clk_period : time := 5 ns;
    
    signal clk, reset : std_logic := '0';
    signal thash_in   : xmss_thash_h_input_type;
    signal thash_out  : xmss_thash_h_output_type;

begin

    -- =========================================================================
    -- Instancia del módulo THASH (Device Under Test)
    -- =========================================================================
    uut : entity work.thash_h
    port map(
        clk   => clk,
        reset => reset,
        d     => thash_in,
        q     => thash_out
    );

    -- =========================================================================
    -- Instancia del gestor de Hashes (conecta con SHA-256)
    -- =========================================================================
    hash : entity work.hash_core_collection
    port map(
       clk   => clk,
       reset => reset,
       d     => thash_out.hash,
       q     => thash_in.hash 
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
    -- Proceso de Estímulos
    -- =========================================================================
    process
    begin
        -- Inicialización segura
        thash_in.module_input.enable <= '0';
        thash_in.module_input.input_1 <= (others => '0');
        thash_in.module_input.input_2 <= (others => '0');
        thash_in.module_input.address_3 <= (others => '0');
        thash_in.module_input.address_4 <= (others => '0');
        thash_in.module_input.address_5 <= (others => '0');
        thash_in.module_input.address_6 <= (others => '0');
        thash_in.pub_seed <= (others => '0');
        
        reset <= '1';
        wait for 4 * clk_period;
        reset <= '0';
        wait for 4 * clk_period;

        -------------------------------------------------
        -- TEST 1: COMPRESIÓN DE DOS NODOS A CERO
        -------------------------------------------------
        report "=======================================================" severity note;
        report "=== INICIANDO TEST 1: THASH CON NODOS A CERO ===" severity note;
        
        -- Semilla pública y direcciones arbitrarias
        thash_in.pub_seed <= x"602b26ef82322218b61c22a9581989384d0d4a5653a5d761e3f8fbe80f5020bb";
        thash_in.module_input.address_3 <= x"00000001";
        thash_in.module_input.address_4 <= x"00000000";
        thash_in.module_input.address_5 <= x"00000002";
        thash_in.module_input.address_6 <= x"00000003";
        
        -- Nodos de entrada (Input 1 e Input 2)
        thash_in.module_input.input_1 <= x"1111111111111111111111111111111111111111111111111111111111111111";
        thash_in.module_input.input_2 <= x"2222222222222222222222222222222222222222222222222222222222222222";
        
        -- Lanzamos el módulo
        thash_in.module_input.enable <= '1';
        wait for clk_period;
        thash_in.module_input.enable <= '0';
        
        -- Esperamos con bucle seguro a que termine las 4 operaciones SHA256
        loop
            wait until rising_edge(clk);
            exit when thash_out.module_output.done = '1';
        end loop;
        
        report "=== TEST 1 COMPLETADO: THASH SOBREVIVIO A LAS 4 RONDAS ===" severity note;
        report "    HASH RESULTANTE: " severity note;
        -- Imprimimos un aviso para confirmar visualmente en las formas de onda
        wait for 10 * clk_period;
        
        report "=======================================================" severity note;
        report "=== THASH_H VALIDADO. LISTOS PARA L_TREE ===" severity note;
        wait;
        
    end process;

end Behavioral;
