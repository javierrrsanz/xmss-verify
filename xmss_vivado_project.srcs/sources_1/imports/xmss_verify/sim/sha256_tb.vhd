library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_comp.ALL;

entity sha256_tb is
end sha256_tb;

architecture default of sha256_tb is
    constant clk_period : time := 10 ns; 
    
    -- Señales del DUT
    signal clk, reset, enable, last, done, mnext : std_logic := '0';
    signal halt : std_logic := '0'; 
    signal message : std_logic_vector(31 downto 0) := (others => '0');
    signal hash : std_logic_vector(255 downto 0);
    
    -- Vectores Esperados (NIST FIPS 180-4)
    constant EXP_EMPTY : std_logic_vector(255 downto 0) := x"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    constant EXP_ABC   : std_logic_vector(255 downto 0) := x"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    constant EXP_MULTI : std_logic_vector(255 downto 0) := x"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1";

    -- Función auxiliar para HEX
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
    uut : entity work.sha256
    port map(
        clk => clk, reset => reset, d.enable => enable, d.last => last, d.halt => halt,
        d.message => message, q.done => done, q.mnext => mnext, q.hash => hash
    );

    clk_process : process
    begin
        clk <= '0'; wait for clk_period / 2;
        clk <= '1'; wait for clk_period / 2;
    end process;

    stim_proc: process
        procedure send_block(
            data_words : in std_logic_vector(0 to 511); 
            is_last    : in boolean;
            is_first   : in boolean
        ) is
        begin
            -- Espera síncrona pura al handshake del núcleo
            if not is_first then
                loop
                    wait until rising_edge(clk);
                    exit when mnext = '1';
                end loop;
            end if;
            
            if is_last then last <= '1'; else last <= '0'; end if;
            
            -- Inyección estricta síncrona de 16 palabras
            for i in 0 to 15 loop
                message <= data_words(i*32 to (i*32)+31);
                wait until rising_edge(clk);
            end loop;
            
            message <= (others => '0');
        end procedure;

    begin
        report "========================================================";
        report " INICIO DE STRESS TEST SHA-256";
        report "========================================================";
        
        reset <= '1'; enable <= '0'; halt <= '0'; last <= '0';
        wait for clk_period * 5;
        wait until rising_edge(clk);
        reset <= '0';
        wait for clk_period * 2;

        ------------------------------------------------------------
        -- TEST 1: EMPTY STRING
        ------------------------------------------------------------
        report "--> TEST 1: Mensaje Vacio (1 Bloque)" severity note;
        wait until rising_edge(clk);
        enable <= '1';
        
        send_block(x"80000000" & x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", true, true);
        
        enable <= '0'; 
        wait until done = '1';
        wait for clk_period;
        
        if hash = EXP_EMPTY then report "    [PASS] Test 1 OK" severity note;
        else report "    [FAIL] Test 1. Got: " & to_hex_string(hash) severity error; end if;
        
        wait for clk_period * 10;
        reset <= '1'; wait for clk_period; reset <= '0';

        ------------------------------------------------------------
        -- TEST 2: "abc"
        ------------------------------------------------------------
        report "--> TEST 2: Mensaje 'abc' (1 Bloque)" severity note;
        wait until rising_edge(clk);
        enable <= '1';
        
        send_block(x"61626380" & x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018", true, true);
        
        enable <= '0';
        wait until done = '1';
        wait for clk_period;

        if hash = EXP_ABC then report "    [PASS] Test 2 OK" severity note;
        else report "    [FAIL] Test 2. Got: " & to_hex_string(hash) severity error; end if;

        wait for clk_period * 10;
        reset <= '1'; wait for clk_period; reset <= '0';

        ------------------------------------------------------------
        -- TEST 3: MULTI-BLOCK (NIST 56 bytes)
        ------------------------------------------------------------
        report "--> TEST 3: Multi-bloque (2 Bloques - Handshake Check)" severity note;
        wait until rising_edge(clk);
        enable <= '1';
        
        send_block(
            x"6162636462636465636465666465666765666768666768696768696a68696a6b" & 
            x"696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f7071" & 
            x"80000000" & 
            x"00000000",  
            false, true 
        );
        
        report "    Bloque 1 enviado. Esperando solicitud de Bloque 2..." severity note;

        send_block(
            x"0000000000000000000000000000000000000000000000000000000000000000" & 
            x"000000000000000000000000000000000000000000000000" & 
            x"00000000" & 
            x"000001C0",  
            true, false 
        );
 
        enable <= '0';
        wait until done = '1';
        wait for clk_period;

        if hash = EXP_MULTI then report "    [PASS] Test 3 OK" severity note;
        else 
            report "    [FAIL] Test 3 (Multi-block). Falla en la transicion?" severity error;
            report "    Got: " & to_hex_string(hash);
        end if;

        report "========================================================";
        report " FIN DE STRESS TEST";
        report "========================================================";
        wait;
    end process;
end default;