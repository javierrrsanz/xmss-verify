library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Librerías estándar para lectura de archivos de texto
use std.textio.all;
use ieee.std_logic_textio.all; 

use work.params.ALL;
use work.xmss_main_typedef.ALL;

entity XMSS_tb_2 is
end XMSS_tb_2;

architecture Behavioral of XMSS_tb_2 is

    -- Configuración del reloj
    constant clk_period : time := 10 ns;

    -- Señales para conectar con el Top Level (DUT)
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '0';
    signal enable      : std_logic := '0';
    signal mlen        : std_logic_vector(31 downto 0) := (others => '0');
    signal done        : std_logic;
    signal valid       : std_logic_vector(15 downto 0);

    -- Señales de la BRAM emulada (Interfaz con el DUT)
    signal bram_en_a   : std_logic;
    signal bram_wen_a  : std_logic;
    signal bram_addr_a : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal bram_din_a  : std_logic_vector(n*8-1 downto 0);
    signal bram_dout_a : std_logic_vector(n*8-1 downto 0) := (others => '0');

    signal bram_en_b   : std_logic;
    signal bram_wen_b  : std_logic;
    signal bram_addr_b : std_logic_vector(BRAM_ADDR_SIZE-1 downto 0);
    signal bram_din_b  : std_logic_vector(n*8-1 downto 0);
    signal bram_dout_b : std_logic_vector(n*8-1 downto 0) := (others => '0');

    -- Definición de la estructura de memoria RAM
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    
    -- Inicializamos vacía, se cargará dinámicamente en el proceso
    signal bram_memory : ram_type := (others => (others => '0'));

begin

    -- 1. INSTANCIA DEL TOP LEVEL (XMSS)
    uut : entity work.XMSS
        port map (
            clk         => clk,
            reset       => reset,
            enable      => enable,
            mlen        => mlen,
            done        => done,
            valid       => valid,
            
            bram_en_a   => bram_en_a,
            bram_wen_a  => bram_wen_a,
            bram_addr_a => bram_addr_a,
            bram_din_a  => bram_din_a,
            bram_dout_a => bram_dout_a,
            
            bram_en_b   => bram_en_b,
            bram_wen_b  => bram_wen_b,
            bram_addr_b => bram_addr_b,
            bram_din_b  => bram_din_b,
            bram_dout_b => bram_dout_b
        );

    -- 2. GENERADOR DE RELOJ
    process
    begin
        clk <= '1';
        wait for clk_period / 2;
        clk <= '0';
        wait for clk_period / 2;
    end process;

    -- 3. EMULADOR DE BRAM DUAL-PORT CON CARGA DINÁMICA DE TEXTIO
    process(clk)
        file mem_file : text;
        variable L : line;
        variable hex_val : std_logic_vector(n*8 - 1 downto 0);
        variable i : integer;
        variable mem_loaded : boolean := false;
    begin
        if rising_edge(clk) then
            
            -- Durante el RESET inicial, leemos el archivo del disco duro
            if reset = '1' then
                if not mem_loaded then
                    -- Ruta absoluta a tu archivo generado por WSL
                    file_open(mem_file, "C:/Users/javie/OneDrive/Escritorio/TFG/XMSS github/xmss-reference-master/xmss-reference-master/firma_memoria.dat", read_mode);
                    i := 0;
                    while not endfile(mem_file) and i < 2**BRAM_ADDR_SIZE loop
                        readline(mem_file, L);
                        if L'length > 0 then
                            hread(L, hex_val);
                            bram_memory(i) <= hex_val;
                            i := i + 1;
                        end if;
                    end loop;
                    file_close(mem_file);
                    mem_loaded := true; -- Evita leer el archivo repetidamente mientras el reset siga a 1
                end if;
                
            -- Cuando NO hay reset, la BRAM funciona normal interactuando con el hardware
            else
                mem_loaded := false; -- Reseteamos el flag por si lanzamos otro reset a mitad de simulación

                -- Puerto A
                if bram_en_a = '1' then
                    if bram_wen_a = '1' then
                        bram_memory(to_integer(unsigned(bram_addr_a))) <= bram_din_a;
                    end if;
                    bram_dout_a <= bram_memory(to_integer(unsigned(bram_addr_a)));
                end if;

                -- Puerto B
                if bram_en_b = '1' then
                    if bram_wen_b = '1' then
                        bram_memory(to_integer(unsigned(bram_addr_b))) <= bram_din_b;
                    end if;
                    bram_dout_b <= bram_memory(to_integer(unsigned(bram_addr_b)));
                end if;
            end if;
        end if;
    end process;

    -- 4. SECUENCIA DE ESTÍMULOS
    process
    begin
        -- Estado inicial y Reset (Esto dispara la lectura del archivo)
        reset <= '1';
        enable <= '0';
        -- Mensaje: "Firma TFG VHDL" (14 bytes = 112 bits)
        mlen <= std_logic_vector(to_unsigned(112, 32));
        
        wait for 100 ns;
        wait until rising_edge(clk);
        reset <= '0';
        wait for 50 ns;

        report "===========================================================" severity note;
        report "=== INICIANDO VERIFICACION AUTOMATIZADA (TB_2)          ===" severity note;
        report "===========================================================" severity note;

        -- El procesador da la orden de inicio al acelerador
        wait until rising_edge(clk);
        enable <= '1';

        -- Monitorización: Esperamos a que el hardware levante la señal 'done'
        wait until done = '1';
        
        report " " severity note;
        report "=== VERIFICACION FINALIZADA ===" severity note;

        -- Comprobación del resultado de seguridad multibit
        if valid = STATUS_VALID then
            report "    [PASS] FIRMA VALIDA. EL HARDWARE VERIFICO CORRECTAMENTE." severity note;
        else
            report "    [FAIL] RESULTADO: FIRMA INVALIDA." severity error;
        end if;
        report "===========================================================" severity note;

        -- Handshake final: bajamos enable tras ver el resultado
        wait for 5 * clk_period;
        enable <= '0';
        
        -- Comprobar si la FSM vuelve a IDLE correctamente
        wait for 10 * clk_period;
        if valid = STATUS_IDLE and done = '0' then
            report "    [INFO] Top Level en reposo correctamente." severity note;
        else
            report "    [FAIL] El Top Level no limpio las senales correctamente." severity error;
        end if;

        wait;
    end process;

end Behavioral;