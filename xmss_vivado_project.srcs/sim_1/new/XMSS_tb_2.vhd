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

    constant clk_period : time := 10 ns;

    -- Señales para conectar con el Top Level (DUT)
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '0';
    signal enable      : std_logic := '0';
    signal mlen        : std_logic_vector(31 downto 0) := (others => '0');
    signal done        : std_logic;
    signal valid       : std_logic_vector(15 downto 0);
    
    -- Interfaz Memoria Externa (Emulación DMA)
    signal sig_base    : std_logic_vector(31 downto 0) := x"00000000";
    signal msg_base    : std_logic_vector(31 downto 0) := x"00020000";
    signal pk_base     : std_logic_vector(31 downto 0) := x"00010000";
    signal mem_req     : std_logic;
    signal mem_addr    : std_logic_vector(31 downto 0);
    signal mem_gnt     : std_logic := '1';
    signal mem_rvalid  : std_logic := '0';
    signal mem_rdata   : std_logic_vector(n*8-1 downto 0) := (others => '0');

    -- Definición de la estructura de memoria RAM para albergar el archivo de texto
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    signal bram_memory : ram_type := (others => (others => '0'));

    -- Señales de latencia para el DMA
    signal mem_pending : std_logic := '0';
    signal mem_addr_lat : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- 1. INSTANCIA DEL TOP LEVEL (XMSS)
    uut : entity work.XMSS
        port map (
            clk         => clk,
            reset       => reset,
            enable      => enable,
            mlen        => mlen,
            sig_base    => sig_base,
            msg_base    => msg_base,
            pk_base     => pk_base,
            done        => done,
            valid       => valid,
            
            mem_req     => mem_req,
            mem_addr    => mem_addr,
            mem_gnt     => mem_gnt,
            mem_rvalid  => mem_rvalid,
            mem_rdata   => mem_rdata
        );

    -- 2. GENERADOR DE RELOJ
    process
    begin
        clk <= '1'; wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

--    -- 3. LECTURA TEXTIO Y EMULADOR DE DMA
--    process(clk)
--        file mem_file : text;
--        variable L : line;
--        variable hex_val : std_logic_vector(n*8 - 1 downto 0);
--        variable i : integer;
--        variable mem_loaded : boolean := false;
--        variable addr_u : unsigned(31 downto 0);
--        variable idx : integer;
--    begin
--        if rising_edge(clk) then
            
--            if reset = '1' then
--                if not mem_loaded then
--                    file_open(mem_file, "C:/Users/javie/OneDrive/Escritorio/TFG/XMSS github/xmss-reference-master/xmss-reference-master/firma_memoria.dat", read_mode);
--                    i := 0;
--                    while not endfile(mem_file) and i < 2**BRAM_ADDR_SIZE loop
--                        readline(mem_file, L);
--                        if L'length > 0 then
--                            hread(L, hex_val);
--                            bram_memory(i) <= hex_val;
--                            i := i + 1;
--                        end if;
--                    end loop;
--                    file_close(mem_file);
--                    mem_loaded := true;
--                end if;
--                mem_pending <= '0';
--                mem_rvalid <= '0';
                
--            else
--                mem_loaded := false;
--                mem_rvalid <= '0';
                
--                if mem_pending = '1' then
--                    addr_u := unsigned(mem_addr_lat);
                    
--                    -- DECODIFICACIÓN INVERSA CORREGIDA
--                    -- pk_base + 4 (Root) -> En tu script en C, el Root se mete en BRAM_XMSS_SIG + 3 (índice 148)
--                    if addr_u = unsigned(pk_base) + 4 then
--                        mem_rdata <= bram_memory(BRAM_XMSS_SIG + 3);  
                    
--                    -- pk_base + 36 (Pub_Seed) -> En tu script, va a BRAM_XMSS_SIG + 2 (índice 147)
--                    elsif addr_u = unsigned(pk_base) + 36 then
--                        mem_rdata <= bram_memory(BRAM_XMSS_SIG + 2);  
                    
--                    elsif addr_u >= unsigned(msg_base) then
--                        idx := to_integer(shift_right(addr_u - unsigned(msg_base), 5));
--                        mem_rdata <= bram_memory(BRAM_MESSAGE + idx); 
                    
--                    else
--                        idx := to_integer(shift_right(addr_u - unsigned(sig_base), 5));
--                        mem_rdata <= bram_memory(idx);              
--                    end if;
                    
--                    mem_rvalid <= '1';
--                    mem_pending <= '0';
--                end if;

--                if mem_req = '1' then
--                    mem_addr_lat <= mem_addr;
--                    mem_pending <= '1';
--                end if;
--            end if;
--        end if;
--    end process;


-- 3. LECTURA TEXTIO Y EMULADOR DE DMA (CON LATENCIA VARIABLE - STRESS TEST)
    process(clk)
        file mem_file : text;
        variable L : line;
        variable hex_val : std_logic_vector(n*8 - 1 downto 0);
        variable i : integer;
        variable mem_loaded : boolean := false;
        variable addr_u : unsigned(31 downto 0);
        variable idx : integer;
        
        -- Variables para emular el atasco del bus OBI
        variable delay_counter : integer := 0;
        variable pseudo_rand   : unsigned(7 downto 0) := x"A5"; -- Semilla aleatoria
    begin
        if rising_edge(clk) then
            
            if reset = '1' then
                if not mem_loaded then
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
                    mem_loaded := true;
                end if;
                mem_pending <= '0';
                mem_rvalid <= '0';
                delay_counter := 0;
                
            else
                mem_loaded := false;
                mem_rvalid <= '0';
                
                -- Generador Pseudoaleatorio básico (LFSR) para variar la latencia
                pseudo_rand := pseudo_rand(6 downto 0) & (pseudo_rand(7) xor pseudo_rand(5) xor pseudo_rand(4) xor pseudo_rand(3));

                -- Emulación de latencia del bus
                if mem_pending = '1' then
                    
                    if delay_counter > 0 then
                        -- El bus está "atascado". El hardware DEBE mantener el HALT arriba.
                        delay_counter := delay_counter - 1;
                    else
                        -- El bus por fin se libera, entregamos el dato.
                        addr_u := unsigned(mem_addr_lat);
                        
                        -- DECODIFICACIÓN INVERSA
                        if addr_u = unsigned(pk_base) + 4 then
                            mem_rdata <= bram_memory(BRAM_XMSS_SIG + 3);  
                        elsif addr_u = unsigned(pk_base) + 36 then
                            mem_rdata <= bram_memory(BRAM_XMSS_SIG + 2);  
                        elsif addr_u >= unsigned(msg_base) then
                            idx := to_integer(shift_right(addr_u - unsigned(msg_base), 5));
                            mem_rdata <= bram_memory(BRAM_MESSAGE + idx); 
                        else
                            idx := to_integer(shift_right(addr_u - unsigned(sig_base), 5));
                            mem_rdata <= bram_memory(idx);              
                        end if;
                        
                        mem_rvalid <= '1';
                        mem_pending <= '0';
                    end if;
                end if;

                -- Capturamos la petición e imponemos un retraso aleatorio (entre 1 y 7 ciclos)
                if mem_req = '1' and mem_pending = '0' then
                    mem_addr_lat <= mem_addr;
                    mem_pending <= '1';
                    -- Imponemos un delay basado en los 3 bits bajos del LFSR
                    delay_counter := to_integer(pseudo_rand(2 downto 0)); 
                end if;
            end if;
        end if;
    end process;

    -- 4. SECUENCIA DE ESTÍMULOS
    process
    begin
        reset <= '1';
        enable <= '0';
        -- Mensaje: "Firma TFG VHDL" (14 bytes = 112 bits)
        mlen <= std_logic_vector(to_unsigned(112, 32));
        wait for 100 ns;
        wait until rising_edge(clk);
        reset <= '0';
        wait for 50 ns;

        report "===========================================================" severity note;
        report "=== INICIANDO VERIFICACION AUTOMATIZADA (TB_2) OBI DMA  ===" severity note;
        report "===========================================================" severity note;

        wait until rising_edge(clk);
        enable <= '1';

        wait until done = '1';
        
        report " " severity note;
        report "=== VERIFICACION FINALIZADA ===" severity note;

        if valid = STATUS_VALID then
            report "    [PASS] FIRMA VALIDA. EL HARDWARE VERIFICO CORRECTAMENTE." severity note;
        else
            report "    [FAIL] RESULTADO: FIRMA INVALIDA." severity error;
        end if;
        report "===========================================================" severity note;

        wait for 5 * clk_period;
        enable <= '0';
        
        wait for 10 * clk_period;
        if valid = STATUS_IDLE and done = '0' then
            report "    [INFO] Top Level en reposo correctamente." severity note;
        else
            report "    [FAIL] El Top Level no limpio las senales correctamente." severity error;
        end if;

        wait;
    end process;

end Behavioral;