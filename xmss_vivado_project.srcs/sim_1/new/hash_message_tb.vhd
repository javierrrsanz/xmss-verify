library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;

entity hash_message_tb is
end hash_message_tb;

architecture Behavioral of hash_message_tb is
    constant clk_period : time := 10 ns;
    
    signal clk, reset : std_logic := '0';
    
    -- Señales de interconexión
    signal hmsg_in  : hash_message_input_type;
    signal hmsg_out : hash_message_output_type;
    signal hash_in  : hash_subsystem_input_type;
    signal hash_out : hash_subsystem_output_type;

    -- Emulador de BRAM (Igual que en el top-level)
    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);
    
    -- VECTORES OFICIALES NIST KAT (Firma 0)
    impure function init_bram return ram_type is
        variable mem_var : ram_type := (others => (others => '0'));
    begin
        -- ROOT 
        mem_var(BRAM_PK) := x"A3F3840A84B677379478D1DFE084F8F528F79C0DF72A9E8A937775EBECCF60F8";
        -- RANDOMNESS (R)
        mem_var(BRAM_XMSS_SIG + 1) := x"83BECF8807135195BC71DE8E314AC7A6ECEE8B5A6FCFF2FDAB00D9494A72968B";
        -- MENSAJE ("Firma TFG VHDL" = 112 bits)
        mem_var(BRAM_MESSAGE) := x"4669726D6120544647205648444C000000000000000000000000000000000000";
        return mem_var;
    end function;

    signal bram_memory : ram_type := init_bram;

    -- Hash esperado EXACTO calculado desde Python
    constant EXP_MHASH : std_logic_vector(255 downto 0) := x"ef68acaa1577a4e834264f6e622310fff106e4b1d65b106a9937272269c0afdd";

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

    -- Instancia del DUT (hash_message)
    uut : entity work.hash_message
        port map(
            clk   => clk,
            reset => reset,
            d     => hmsg_in,
            q     => hmsg_out
        );

    -- Instancia del Hash Core (que incluye el absorb_message validado)
    hash_core : entity work.hash_core_collection
        port map(
            clk   => clk,
            reset => reset,
            d     => hash_in,
            q     => hash_out
        );

    -- Cableado
    hmsg_in.hash <= hash_out;
    hash_in      <= hmsg_out.hash;

    -- Emulador BRAM (Lectura asíncrona/síncrona para el bus)
    process(clk)
    begin
        if rising_edge(clk) then
            if hmsg_out.bram.en = '1' then
                hmsg_in.bram.dout <= bram_memory(to_integer(unsigned(hmsg_out.bram.addr)));
            end if;
        end if;
    end process;

    -- Generador de Reloj
    clk_process : process
    begin
        clk <= '0'; wait for clk_period / 2;
        clk <= '1'; wait for clk_period / 2;
    end process;

    -- Proceso de Estímulos
    stim_proc: process
    begin
        hmsg_in.module_input.enable <= '0';
        hmsg_in.module_input.index  <= (others => '0');
        hmsg_in.module_input.mlen   <= 0;
        
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        wait for 5 * clk_period;

        report "=======================================================" severity note;
        report " INICIANDO PRUEBA DE HASH_MESSAGE (KAT OFICIAL XMSS)" severity note;
        report "=======================================================" severity note;

        wait until rising_edge(clk);
        
        -- Configuramos los parámetros oficiales de la Firma 0
        hmsg_in.module_input.index <= to_unsigned(0, tree_height);
        hmsg_in.module_input.mlen  <= 112; -- Longitud de "Firma TFG VHDL" en bits
        hmsg_in.module_input.enable <= '1';
        
        wait for clk_period;
        hmsg_in.module_input.enable <= '0';


     -- Esperamos a que finalice la orquestación
        loop
            wait until rising_edge(clk);
            exit when hmsg_out.module_output.done = '1';
        end loop;
        
        -- Añadimos 1 ciclo de espera para alinearnos con el registro r.mhash
        wait until rising_edge(clk); 
        
        report "    [MHASH OBTENIDO]: " & to_hex_string(hmsg_out.module_output.mhash) severity note;
       
        if hmsg_out.module_output.mhash = EXP_MHASH then
            report "    [PASS] El calculo de mhash coincide con el vector oficial." severity note;
        else
            report "    [FAIL] El mhash no coincide. Posible perdida de sincronizacion con el Hash Core." severity error;
        end if;
        
        report "=======================================================" severity note;
        wait;
    end process;

end Behavioral;
