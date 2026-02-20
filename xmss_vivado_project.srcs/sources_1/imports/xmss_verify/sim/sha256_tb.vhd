library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sha_comp.ALL;

entity sha256_tb is
end sha256_tb;

architecture Behavioral of sha256_tb is
    constant clk_period : time := 10 ns; 
    
    -- Señales del DUT
    signal clk, reset, enable, last, done, mnext : std_logic := '0';
    signal halt : std_logic := '0'; 
    signal message : std_logic_vector(31 downto 0) := (others => '0');
    signal hash : std_logic_vector(255 downto 0);
    
    -- Vectores Esperados (NIST FIPS 180-4)
    constant EXP_EMPTY : std_logic_vector(255 downto 0) := x"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    constant EXP_ABC   : std_logic_vector(255 downto 0) := x"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    -- Vector multi-bloque (56 bytes): "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
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
            data_words : in std_logic_vector(0 to 511); -- 16 palabras de 32 bits concatenadas
            is_last    : in boolean
        ) is
        begin
            -- Esperar a que el core pida datos (o sea el inicio)
            if enable = '1' and mnext = '0' then
                wait until mnext = '1';
            end if;
            
            if is_last then last <= '1'; else last <= '0'; end if;
            
            -- Inyectar 16 palabras (una por ciclo)
            for i in 0 to 15 loop
                message <= data_words(i*32 to (i*32)+31);
                wait for clk_period;
            end loop;
            
            -- Limpiar bus por seguridad
            message <= (others => '0');
        end procedure;

    begin
        report "========================================================";
        report " INICIO DE STRESS TEST SHA-256";
        report "========================================================";
        
        reset <= '1'; enable <= '0'; halt <= '0'; last <= '0';
        wait for clk_period * 5;
        reset <= '0';
        wait for clk_period * 2;

        ------------------------------------------------------------
        -- TEST 1: EMPTY STRING
        ------------------------------------------------------------
        report "--> TEST 1: Mensaje Vacio (1 Bloque)" severity note;
        enable <= '1';
        -- Padding: 1 bit '1' (0x80) + ceros + Length(0)
        -- Palabra 0: 80000000, Resto 0
        send_block(x"80000000" & x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", true);
        
        enable <= '0'; -- Ya enviamos todo
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
        enable <= '1';
        -- "abc" = 61 62 63. Padding bit = 80. -> Palabra 0: 61626380
        -- Longitud = 24 bits (0x18). Va al final (Palabra 15).
        send_block(x"61626380" & x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018", true);
        
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
        enable <= '1';
        
        -- BLOQUE 1: 56 bytes de datos + 0x80 (padding).
        -- 56 bytes llenan las palabras 0 a 13 completas.
        -- Palabra 14: Empieza con el byte de padding 0x80, resto 0.
        -- Palabra 15: 0x00... (No cabe la longitud aqui).
        -- Datos: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        -- Hex: 61626364 62636465 ...
        
        -- Enviamos primer bloque (last = false)
        send_block(
            x"6162636462636465636465666465666765666768666768696768696a68696a6b" & -- W0-W7
            x"696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f7071" & -- W8-W13 (Datos)
            x"80000000" & -- W14 (Padding start)
            x"00000000",  -- W15 (Relleno, no cabe len)
            false -- NO es el último
        );
        
        -- El procedimiento send_block espera automáticamente a 'mnext' si lo llamamos otra vez
        report "    Bloque 1 enviado. Esperando solicitud de Bloque 2..." severity note;

        -- BLOQUE 2: Todo ceros excepto la longitud al final.
        -- Longitud = 448 bits = 0x1C0
        send_block(
            x"0000000000000000000000000000000000000000000000000000000000000000" & -- W0-W7
            x"000000000000000000000000000000000000000000000000" & -- W8-W13
            x"00000000" & -- W14 (Len High)
            x"000001C0",  -- W15 (Len Low = 448)
            true -- AHORA sí es el último
        );
 
        enable <= '0';
        wait until done = '1';
        wait for clk_period;

        if hash = EXP_MULTI then report "    [PASS] Test 3 OK" severity note;
        else 
            report "    [FAIL] Test 3 (Multi-block). Falla en la transicion?" severity error;
            report "    Got: " & to_hex_string(hash);
            report "    Exp: " & to_hex_string(EXP_MULTI);
        end if;

        report "========================================================";
        report " FIN DE STRESS TEST";
        report "========================================================";
        wait;
    end process;
end Behavioral;