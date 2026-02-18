library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_comp.ALL;

-- Librerías necesarias para escribir en consola
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity sha256_tb is
end sha256_tb;

architecture Behavioral of sha256_tb is

    -- Constantes del reloj
    constant clk_period : time := 10 ns;

    -- Señales de conexión
    signal clk : std_logic := '0';
    signal reset : std_logic := '0';
    signal enable : std_logic := '0';
    signal last : std_logic := '0';
    signal message : std_logic_vector(31 downto 0) := (others => '0');
    signal done : std_logic;
    signal mnext : std_logic;
    signal hash : std_logic_vector(255 downto 0);

    -- Función auxiliar para convertir vector a texto HEX (para que se lea bien en consola)
    function to_hstring(slv : std_logic_vector) return string is
        variable hex_len : integer := slv'length/4;
        variable ret_str : string(1 to hex_len);
        variable nibble  : std_logic_vector(3 downto 0);
    begin
        for i in 0 to hex_len-1 loop
            nibble := slv(slv'high - i*4 downto slv'high - i*4 - 3);
            case nibble is
                when "0000" => ret_str(i+1) := '0'; when "0001" => ret_str(i+1) := '1';
                when "0010" => ret_str(i+1) := '2'; when "0011" => ret_str(i+1) := '3';
                when "0100" => ret_str(i+1) := '4'; when "0101" => ret_str(i+1) := '5';
                when "0110" => ret_str(i+1) := '6'; when "0111" => ret_str(i+1) := '7';
                when "1000" => ret_str(i+1) := '8'; when "1001" => ret_str(i+1) := '9';
                when "1010" => ret_str(i+1) := 'A'; when "1011" => ret_str(i+1) := 'B';
                when "1100" => ret_str(i+1) := 'C'; when "1101" => ret_str(i+1) := 'D';
                when "1110" => ret_str(i+1) := 'E'; when "1111" => ret_str(i+1) := 'F';
                when others => ret_str(i+1) := 'X';
            end case;
        end loop;
        return ret_str;
    end function;

begin

    -- Instancia (Mantenemos el halt => '0' que es vital para que funcione)
    uut : entity work.sha256
    port map(
        clk       => clk,
        reset     => reset,
        d.enable  => enable,
        d.last    => last,
        d.message => message,
        d.halt    => '0', 
        q.done    => done,
        q.mnext   => mnext,
        q.hash    => hash
    );

    -- Generador de Reloj
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Proceso de Estímulos y Reportes
    stim_proc: process
        variable l : line; -- Línea para escribir en consola
        variable expected_hash : std_logic_vector(255 downto 0);
    begin		
        -- Cabecera
        write(l, string'("============================================")); writeline(output, l);
        write(l, string'("   INICIANDO TESTBENCH SHA-256              ")); writeline(output, l);
        write(l, string'("============================================")); writeline(output, l);
        wait for 100 ns;

        -----------------------------------------------------------------
        -- TEST 1: Mensaje vacío (Padding only)
        -----------------------------------------------------------------
        write(l, string'("TEST 1: Hash de mensaje vacio...")); writeline(output, l);
        
        reset <= '1'; enable <= '0'; last <= '0';
        wait for clk_period*10;
        reset <= '0';
        
        -- Lógica original de estímulos
        message <= (31 => '1', others => '0'); -- 0x80000000
        enable <= '1';
        wait for clk_period*1.5; -- Sincronización fina
        message <= (others => '0');
        
        wait until mnext = '1';
        last <= '1';
        message <= (others => '0'); -- Longitud 0
        
        wait until done = '1';
        wait for clk_period; -- Esperar estabilidad

        -- VERIFICACIÓN TEST 1
        expected_hash := x"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        write(l, string'("   Obtenido: ") & to_hstring(hash)); writeline(output, l);
        
        if hash = expected_hash then
            write(l, string'("   RESULTADO: [CORRECTO]")); writeline(output, l);
        else
            write(l, string'("   RESULTADO: [ERROR] - No coincide con el esperado")); writeline(output, l);
        end if;
        write(l, string'("--------------------------------------------")); writeline(output, l);

        -----------------------------------------------------------------
        -- TEST 2: Bloque de 1s
        -----------------------------------------------------------------
        write(l, string'("TEST 2: Bloque de '1's...")); writeline(output, l);

        wait for clk_period*20;
        reset <= '1'; enable <= '0'; last <= '0';
        wait for clk_period*5;
        reset <= '0'; enable <= '1';
        
        -- Lógica original de estímulos
        message <= (others => '1'); -- 0xFFFFFFFF
        wait until mnext = '1';
        
        last <= '0';
        message <= (31 => '1', others => '0'); -- Padding
        wait for clk_period*4;
        message <= (others => '0');
        
        -- Espera manual que tenías en tu código original
        wait for clk_period*14; 
        
        message <= (9 => '1', others => '0'); -- Longitud 512 bits
        wait until mnext = '1';
        last <= '1';
        enable <= '0';
        
        wait until done = '1';
        wait for clk_period;

        -- VERIFICACIÓN TEST 2
        expected_hash := x"8667e718294e9e0df1d30600ba3eeb201f764aad2dad72748643e4a285e1d1f7";
        write(l, string'("   Obtenido: ") & to_hstring(hash)); writeline(output, l);
        
        if hash = expected_hash then
            write(l, string'("   RESULTADO: [CORRECTO]")); writeline(output, l);
        else
            write(l, string'("   RESULTADO: [ERROR] - No coincide con el esperado")); writeline(output, l);
        end if;
        write(l, string'("--------------------------------------------")); writeline(output, l);

        -----------------------------------------------------------------
        -- TEST 3: "asdf" + "ASDF"
        -----------------------------------------------------------------
        write(l, string'("TEST 3: Mensaje 'asdfASDF'...")); writeline(output, l);

        wait for clk_period*20;
        reset <= '1'; enable <= '0'; last <= '0';
        wait for clk_period*5;
        reset <= '0'; enable <= '1';
        
        -- Lógica original de estímulos
        message <= x"61736466"; -- "asdf"
        wait for clk_period;
        message <= x"41534446"; -- "ASDF"
        wait for clk_period;
        message <= (31 => '1', others => '0'); -- Padding
        wait for clk_period;
        message <= (others => '0');
        
        wait for clk_period*12; -- Relleno
        
        message <= x"00000040"; -- Longitud 64 bits
        
        wait until mnext = '1';
        last <= '1';
        enable <= '0';
        
        wait until done = '1';
        wait for clk_period;

        -- VERIFICACIÓN TEST 3
        expected_hash := x"f0e4c2f76c58916ec258f246851bea091d14d4247a2fc3e18694461b1816e13b";
        write(l, string'("   Obtenido: ") & to_hstring(hash)); writeline(output, l);
        
        if hash = expected_hash then
            write(l, string'("   RESULTADO: [CORRECTO]")); writeline(output, l);
        else
            write(l, string'("   RESULTADO: [ERROR] - No coincide con el esperado")); writeline(output, l);
        end if;
        
        write(l, string'("============================================")); writeline(output, l);
        write(l, string'("   FIN DE LA SIMULACION                     ")); writeline(output, l);
        write(l, string'("============================================")); writeline(output, l);

        wait;
    end process;

end Behavioral;