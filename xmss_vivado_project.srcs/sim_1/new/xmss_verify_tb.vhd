library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.xmss_main_typedef.ALL;
use work.params.ALL;
use work.wots_comp.ALL;

entity xmss_verify_tb is
end xmss_verify_tb;

architecture Behavioral of xmss_verify_tb is
    constant clk_period : time := 5 ns;
    signal clk, reset : std_logic := '0';

    signal vrfy_in  : xmss_verify_input_type;
    signal vrfy_out : xmss_verify_output_type;
    signal hmsg_in  : hash_message_input_type;
    signal hmsg_out : hash_message_output_type;
    signal wots_in  : wots_input_type;
    signal wots_out : wots_output_type;
    signal ltree_in : xmss_l_tree_input_type;
    signal ltree_out: xmss_l_tree_output_type;
    signal thash_in : xmss_thash_h_input_type;
    signal thash_out: xmss_thash_h_output_type;
    signal hash_in  : hash_subsystem_input_type;
    signal hash_out : hash_subsystem_output_type;

    signal bram_dout_a_reg, bram_dout_b_reg : std_logic_vector(255 downto 0) := (others => '0');
    
    -- =====================================================================
    -- INYECCIÓN DEL TEST VECTOR KAT OFICIAL (NIST / RFC 8391)
    -- =====================================================================
    
    -- Semilla Publica Oficial
    constant PUB_SEED : std_logic_vector(255 downto 0) := x"F223F76B2EA8E560ECCAAAFA00B6B1672EFE10C571FB4977FB32DC99779ED023";

    type ram_type is array (0 to 2**BRAM_ADDR_SIZE - 1) of std_logic_vector(n*8 - 1 downto 0);

    impure function init_bram return ram_type is
        variable mem_var : ram_type := (others => (others => '0'));
    begin
        -- El módulo hash_message lee la raíz desde aquí (Dirección 0)
        mem_var(BRAM_PK) := x"B061F518F7AB552C4390C3F635289BE1051D025CD750D0C31D3F6534A2E0DE49";
        -- 1. INDICE (Alineado al LSB para VHDL)
        mem_var(BRAM_XMSS_SIG) := x"0000000000000000000000000000000000000000000000000000000000000000";

        -- 2. RANDOMNESS (R)
        mem_var(BRAM_XMSS_SIG + 1) := x"92BE94DA7F8589C1C081AA24DD6D46C599B445109BBC93A4A9710BBAF36BC6B4";

        -- 3. PUB_SEED
        mem_var(BRAM_XMSS_SIG + 2) := PUB_SEED;

        -- 4. ROOT CALCULADA POR EL CÓDIGO EN C (La que debe abrir el "Candado")
        mem_var(BRAM_XMSS_SIG + 3) := x"B061F518F7AB552C4390C3F635289BE1051D025CD750D0C31D3F6534A2E0DE49";

        -- 5. MENSAJE: "Firma TFG VHDL" (Hex: 4669726D6120544647205648444C, padding con ceros a 256 bits)
        mem_var(BRAM_MESSAGE) := x"4669726D6120544647205648444C000000000000000000000000000000000000";

        -- 6. LOS 67 BLOQUES DE LA FIRMA WOTS+
        mem_var(BRAM_XMSS_SIG_WOTS + 0) := x"B721FEA90665EAA88FAB68264981ADBE2B21F73874CCFCE9EDA855BFD2B3F06C";
        mem_var(BRAM_XMSS_SIG_WOTS + 1) := x"DF5AB31E1405BF88A8450058EC6A8554CA4AD9094B408AA323C95DB9A753271C";
        mem_var(BRAM_XMSS_SIG_WOTS + 2) := x"D0200AC7BB19924FDC3D32C64A99A6CD380C730EACDF70A476DE79E9597369E8";
        mem_var(BRAM_XMSS_SIG_WOTS + 3) := x"142F9D56DE6B13D6AE8620A264AF6DC16FE374DCDED4F62BFCB413449642F8EE";
        mem_var(BRAM_XMSS_SIG_WOTS + 4) := x"0D3276DC264922E76527E313B4A035C20A60DF31CDB8383EED8A505DD7F4FEB3";
        mem_var(BRAM_XMSS_SIG_WOTS + 5) := x"25EFFB12B067B6CC39CD93C09940268ED8263099AC7DAA9C04252F949B4F62C7";
        mem_var(BRAM_XMSS_SIG_WOTS + 6) := x"6A2609B7D7C4F43410722EC007BE4CA39DB764C2868B738E9C8DAE2A9693CB15";
        mem_var(BRAM_XMSS_SIG_WOTS + 7) := x"B42629FE5CD4471E4FD1623D9842F50EF32BD8955B8E36BE465FC6AA2865668E";
        mem_var(BRAM_XMSS_SIG_WOTS + 8) := x"8AB1FD0DA043220089DE38065C27C0843BAD37EC183702F1AC951C97055DAEFF";
        mem_var(BRAM_XMSS_SIG_WOTS + 9) := x"FFEC136CAEE23D72DE2D19C1F6A62AD72B5E723A5D0795335E7C3336D40E7043";
        mem_var(BRAM_XMSS_SIG_WOTS + 10) := x"E1ACDB4199C09ED4BF56BFA1D2CA73FF521AF62AFD500AE3B0F73F1F603B4ADA";
        mem_var(BRAM_XMSS_SIG_WOTS + 11) := x"0F18509420DD69B1C244C00CB120CE6A42E4FE8C0CDB67E0CDD5F0F794D22778";
        mem_var(BRAM_XMSS_SIG_WOTS + 12) := x"5CA514DF7B53EB773B3F0EFF0E3CA0584A5918452B6068CDF48B05B5DAF5801F";
        mem_var(BRAM_XMSS_SIG_WOTS + 13) := x"C0081EF8DFEA3FE4320F09AF3BBE2C602958DF1C87154D2A3CFBB9770C04A9C4";
        mem_var(BRAM_XMSS_SIG_WOTS + 14) := x"5674DE5FB352B31BC55EDED26BB8C4DBE947745AFD1097AE7BC2059C058BDA2B";
        mem_var(BRAM_XMSS_SIG_WOTS + 15) := x"B7EC2510C2B49152B5141706A7E69E0DED5E5017D9EFC7552F93D8669D3AD3C5";
        mem_var(BRAM_XMSS_SIG_WOTS + 16) := x"94341E9B9D47AD4E57765EEC1A7AFDE0D179DDAC1DA6D7034E35DCAAA10E06AC";
        mem_var(BRAM_XMSS_SIG_WOTS + 17) := x"123C966A6C85EF6AABC6CE74A0C12F276D6C9A44184DC753E9693C9E286D8ACC";
        mem_var(BRAM_XMSS_SIG_WOTS + 18) := x"916BA4F82483902D78A48AB83A31C3973384C8DF261BD63CB1D8C8B7F72469AC";
        mem_var(BRAM_XMSS_SIG_WOTS + 19) := x"090C2E4E5EC689C54398397A5D11EE5A7B5954998FAC1E25FC801D5BC1A976AF";
        mem_var(BRAM_XMSS_SIG_WOTS + 20) := x"D3713EED73F1494DB18A6CA9D029507605367594A32BA1529FE59313D72C0D74";
        mem_var(BRAM_XMSS_SIG_WOTS + 21) := x"AEBC04AC3C52198D6B0FC78F63043AEF88A064E926923D0488B2F10D8968EA82";
        mem_var(BRAM_XMSS_SIG_WOTS + 22) := x"F4B80731D3A6B38386BD90D03B2FCE24408C0D71E5C86287244D9C0268A4D294";
        mem_var(BRAM_XMSS_SIG_WOTS + 23) := x"4A438A4F5F15700449F61C3D2DAD3748F9BE5559C5FBC8103A1FEFCC0F20B737";
        mem_var(BRAM_XMSS_SIG_WOTS + 24) := x"121374BD1E2441D4D0AFA940CBCBE1D1A3D61C280A440CADDD69BBA73318C391";
        mem_var(BRAM_XMSS_SIG_WOTS + 25) := x"27AECA97D8CC74086B054A9BE4E39693C4AAC687DAEF965F2D7202BC0694FD24";
        mem_var(BRAM_XMSS_SIG_WOTS + 26) := x"932083E86168C938070CC35007CF82D7D22D183A738268C2671CAEB77F26E27D";
        mem_var(BRAM_XMSS_SIG_WOTS + 27) := x"AF5A011BF71BBF96743ADA9A040936052DB8940BFEF939580655B66CA661F4C2";
        mem_var(BRAM_XMSS_SIG_WOTS + 28) := x"5884B36CB7EC2217828F339BD7AAC667CFE059E1E7230554D36C3CBB035E8140";
        mem_var(BRAM_XMSS_SIG_WOTS + 29) := x"4833DCAF3B82789B4969BFCB0A7BAAA0A8A9AE6BA76DD9973CC828AA94F01720";
        mem_var(BRAM_XMSS_SIG_WOTS + 30) := x"33B8F3563B2FC3ED44F5A3905CA547B8E3CAA698B854709C5526EB8F7D63D967";
        mem_var(BRAM_XMSS_SIG_WOTS + 31) := x"9ED9CA5A0B8AE6038C1025890DD6540EC11A988F3BEA53D4A24F257C0D441DFC";
        mem_var(BRAM_XMSS_SIG_WOTS + 32) := x"26B3C0E60DEF8027EFFD3DE1CDF261C6DE978543265867DFA2D730CA3ADFDC5A";
        mem_var(BRAM_XMSS_SIG_WOTS + 33) := x"189DC9517D73AACC3257B6106954E8D6F8618164487AEA66F73C2F3443C6D719";
        mem_var(BRAM_XMSS_SIG_WOTS + 34) := x"12576AB5942F694A10A3AFAA7AD71C27146C9ED1022FD0F339E3051561F96A39";
        mem_var(BRAM_XMSS_SIG_WOTS + 35) := x"60AF968E368E8BF4B48AAA36188F473CCD89E328FFFF36047D730582838BBD80";
        mem_var(BRAM_XMSS_SIG_WOTS + 36) := x"3DF69471228232B36BE7F00ED7D90CAC1DAFCB929A8725B252611CA1BF0DEEC9";
        mem_var(BRAM_XMSS_SIG_WOTS + 37) := x"DBCF27E1D2CC06C31BC5E11858B59298A8077B4F1E5AA1EEC4ECD2455DC81E00";
        mem_var(BRAM_XMSS_SIG_WOTS + 38) := x"245FD4F4B0DAEA1442C67286BFADE2E696A76A96B18EBE14FC9C0C1422AF9B44";
        mem_var(BRAM_XMSS_SIG_WOTS + 39) := x"AEC57B2234DBF21157ECE4B9AE2A2F5F50FAADB25C38A2295484651A7FE0B02F";
        mem_var(BRAM_XMSS_SIG_WOTS + 40) := x"3C0712EC497C188E2C20902BD38CB6B6BD65EFA2816F58A32EB6F434199169E5";
        mem_var(BRAM_XMSS_SIG_WOTS + 41) := x"7D50AE471DA140EB4E7314A6A496DB995280B7BF8ECEC8BB465588ABC73262A7";
        mem_var(BRAM_XMSS_SIG_WOTS + 42) := x"32B4E37E199C724DB8972B5046C36304BDFBD9CB2CE95763BB6643327924A421";
        mem_var(BRAM_XMSS_SIG_WOTS + 43) := x"8E1608C6472E2C8881E932903343148856286DA009CB7C92BC3F54F0AE39F403";
        mem_var(BRAM_XMSS_SIG_WOTS + 44) := x"90565BD2D1E42649A08B092CE862DC8ABDFB059B7A7B7561C3BFADEB00F3936A";
        mem_var(BRAM_XMSS_SIG_WOTS + 45) := x"C753AA192F2061AD374C1604524055BEF7B3BCD0325D2B1F3EEC1CFDAC4AC355";
        mem_var(BRAM_XMSS_SIG_WOTS + 46) := x"21E4F235B65A9636A3936E00C7CA27304C7F1D811D3D52D0B5E2DC3EF44477B1";
        mem_var(BRAM_XMSS_SIG_WOTS + 47) := x"DBCFE30E456FBF7C2B1574FA287B3E50F8EA717E4D0141E1D6FEAB1B7A26A712";
        mem_var(BRAM_XMSS_SIG_WOTS + 48) := x"3D3695F28DCFE58A9203C622B2B9CBE09535F7E7F745659BA860EEF64AD61092";
        mem_var(BRAM_XMSS_SIG_WOTS + 49) := x"5BD7A6312137255DBCCB75EFF42B4A105BAECA57827DE0094410214D88BC4A3A";
        mem_var(BRAM_XMSS_SIG_WOTS + 50) := x"0FD176C1632738F9F1C87C3C9CD488ABD4475C546A21D0C7613D8BF367F31776";
        mem_var(BRAM_XMSS_SIG_WOTS + 51) := x"8F029627489C6A3DBCBEC05D81BA19D7760BD93C56379798CC3C28C379BD4465";
        mem_var(BRAM_XMSS_SIG_WOTS + 52) := x"C9AD274085C34289088988BA7D2DDC9E3E5B1037A9876E6D708685D1DAA4734B";
        mem_var(BRAM_XMSS_SIG_WOTS + 53) := x"A34BBECBFC9787FFD59A7A631CFF3287D983C2EA0B4AC348276720AE3DE36769";
        mem_var(BRAM_XMSS_SIG_WOTS + 54) := x"37360224DC1D12F84033D78BDB43BD1331E3D11B98F8C8FC965E84DA31695AE2";
        mem_var(BRAM_XMSS_SIG_WOTS + 55) := x"BBDCA877C35EAD82EEF45709045F3EC3D54CA8262CCA415AD10699B29993AEE7";
        mem_var(BRAM_XMSS_SIG_WOTS + 56) := x"47CD29AAAD28A735F4B00F63E04ED10635C2CD987510349B6ECA9F25D1AC190A";
        mem_var(BRAM_XMSS_SIG_WOTS + 57) := x"B96D54FAC0985158B2C857956E69B520B32924002BA386ED5021448D186E5A47";
        mem_var(BRAM_XMSS_SIG_WOTS + 58) := x"5ADE6DED22B6FBEC4558B152B77A60B138914CF7A9C97779173E0FABA1F97378";
        mem_var(BRAM_XMSS_SIG_WOTS + 59) := x"D806AFD1CCCEAECEDA5CD37A9DEF3B3531E4B4EE03A3ADCEF241B8BD7AA2EA63";
        mem_var(BRAM_XMSS_SIG_WOTS + 60) := x"54AD4619FD89764D275A679052D0F12505D0CFF35D5D61258D2BAE920DDCB6A1";
        mem_var(BRAM_XMSS_SIG_WOTS + 61) := x"0C0407AF6498181FE22D669FD078EAD2DB8E3D95AED3242221657863D8DB8A12";
        mem_var(BRAM_XMSS_SIG_WOTS + 62) := x"01D1EB421B4382A4D5E38F38ABE4D518F52DC0DE1A023C884FF4D4B3715C2341";
        mem_var(BRAM_XMSS_SIG_WOTS + 63) := x"1DFF50E44EA20719A5823ABC4D4C209F8B4492BCE6ECEA1A20F526471E128298";
        mem_var(BRAM_XMSS_SIG_WOTS + 64) := x"0842B04CB90FC5693ECDFC872A5A772D612FC33615B372B69A76BCAE1BEAE890";
        mem_var(BRAM_XMSS_SIG_WOTS + 65) := x"459D736E85D1CC96B46D3F8D384B3A1CA141A62CEA0AF45CD5C7494AAD9E2B16";
        mem_var(BRAM_XMSS_SIG_WOTS + 66) := x"23199FA77C13B41379F26B9E02D7799C82A559EDA8D4B7CD0F2DBCD4263FF0EC";

        -- 7. LOS 10 BLOQUES DEL AUTH PATH (Camino hacia la Raíz)
        mem_var(BRAM_XMSS_SIG_AUTH + 0) := x"9457564E89AAF733C9962ED94FAF7AD7CA25F4E8D5729C0275A6869CA5D99CF7";
        mem_var(BRAM_XMSS_SIG_AUTH + 1) := x"2C0211FA0323D8BEFB85ED36210AEDC8F6A5B457621608355CE5D951CAB5D5D1";
        mem_var(BRAM_XMSS_SIG_AUTH + 2) := x"A8E9F0BAC8955833431DB6005D3EA6D96EF0C0449D52A96CEF8A15B33D8F51D0";
        mem_var(BRAM_XMSS_SIG_AUTH + 3) := x"D3ABB39B9440BA7D377A140BE655109B4B26EC23A4CFEE1913CDBE7AD6017E82";
        mem_var(BRAM_XMSS_SIG_AUTH + 4) := x"A9AE9CE3BEAED835AB3A158F2A41E87F3D0B99E0DA692BAD2832E4D3A934436A";
        mem_var(BRAM_XMSS_SIG_AUTH + 5) := x"50AC94E2BB477F3E14E9192682354A2D56A5F73AC707318071D91A92A40A8271";
        mem_var(BRAM_XMSS_SIG_AUTH + 6) := x"175B7359CC0C6F3E0D029E3E36A1AACCF6AE1A1282762CA957CF68F3C8FC465A";
        mem_var(BRAM_XMSS_SIG_AUTH + 7) := x"41198F674550651A592EB1DE45F4492F4A69749137903C8BA04CDA01080AF753";
        mem_var(BRAM_XMSS_SIG_AUTH + 8) := x"E7F785C65CF478C4D71A16DB64868C96B21969588C3A6A7181F6AA81B5288C7D";
        mem_var(BRAM_XMSS_SIG_AUTH + 9) := x"ED7C9488E6FD2A2D23AA66F4D3DDC0A543CEBE942CD1D335A4DC9FE27CB5C5B7";

        return mem_var;
    end function;

    signal bram_memory : ram_type := init_bram;
    signal tb_enable : std_logic := '0';

begin

    -- Conexiones Síncronas
    vrfy_in.enable <= tb_enable;
    -- EL MENSAJE MIDE EXACTAMENTE 14 BYTES -> 14 * 8 = 112 BITS
    vrfy_in.mlen <= 112; 
    vrfy_in.wots <= wots_out.module_output;
    vrfy_in.l_tree <= ltree_out.module_output;
    vrfy_in.thash <= thash_out.module_output;
    vrfy_in.hash_message <= hmsg_out.module_output;
    vrfy_in.bram.a.dout <= bram_dout_a_reg;
    vrfy_in.bram.b.dout <= bram_dout_b_reg;

    process(vrfy_out, hash_out, bram_dout_b_reg) begin
        hmsg_in.module_input <= vrfy_out.hash_message;
        hmsg_in.hash <= hash_out;
        hmsg_in.bram.dout <= bram_dout_b_reg;
    end process;

    process(vrfy_out, hash_out, bram_dout_b_reg) begin
        wots_in.module_input <= vrfy_out.wots;
        wots_in.pub_seed <= PUB_SEED;
        wots_in.bram_b.dout <= bram_dout_b_reg;
        wots_in.hash <= hash_out;
    end process;

    process(vrfy_out, ltree_out, thash_out, hash_out, bram_dout_a_reg, bram_dout_b_reg) begin
        ltree_in.module_input <= vrfy_out.l_tree;
        ltree_in.bram.a.dout <= bram_dout_a_reg;
        ltree_in.bram.b.dout <= bram_dout_b_reg;
        ltree_in.thash <= thash_out.module_output;
        
        if vrfy_out.mode_select_l1 = "11" then
            thash_in.module_input <= ltree_out.thash;
        else
            thash_in.module_input <= vrfy_out.thash;
        end if;
        thash_in.pub_seed <= PUB_SEED;
        thash_in.hash <= hash_out;
    end process;

    hash_in <= hmsg_out.hash when vrfy_out.mode_select_l1 = "10" else 
               wots_out.hash when vrfy_out.mode_select_l1 = "01" else 
               thash_out.hash;

    -- Instancias de tu Hardware Real
    uut : entity work.xmss_verify port map(clk => clk, reset => reset, d => vrfy_in, q => vrfy_out);
    hms: entity work.hash_message port map(clk => clk, reset => reset, d => hmsg_in, q => hmsg_out);
    wts: entity work.wots port map(clk => clk, reset => reset, d => wots_in, q => wots_out);
    ltr: entity work.l_tree port map(clk => clk, reset => reset, d => ltree_in, q => ltree_out);
    ths: entity work.thash_h port map(clk => clk, reset => reset, d => thash_in, q => thash_out);
    hco: entity work.hash_core_collection port map(clk => clk, reset => reset, d => hash_in, q => hash_out);

    process begin
        clk <= '1'; wait for clk_period / 2;
        clk <= '0'; wait for clk_period / 2;
    end process;

    -- Multiplexor de Memoria BRAM
    process(clk)
        variable addr_a, addr_b : integer;
        variable wen_a, wen_b : std_logic;
        variable din_a, din_b : std_logic_vector(255 downto 0);
    begin
        if rising_edge(clk) then
            if vrfy_out.mode_select_l1 = "01" then
                addr_a := to_integer(unsigned(wots_out.bram.a.addr)); wen_a := wots_out.bram.a.wen; din_a := wots_out.bram.a.din;
                addr_b := to_integer(unsigned(wots_out.bram.b.addr)); wen_b := wots_out.bram.b.wen; din_b := wots_out.bram.b.din;
            elsif vrfy_out.mode_select_l1 = "11" then
                addr_a := to_integer(unsigned(ltree_out.bram.a.addr)); wen_a := ltree_out.bram.a.wen; din_a := ltree_out.bram.a.din;
                addr_b := to_integer(unsigned(ltree_out.bram.b.addr)); wen_b := ltree_out.bram.b.wen; din_b := ltree_out.bram.b.din;
            else
                addr_a := to_integer(unsigned(vrfy_out.bram.a.addr)); wen_a := vrfy_out.bram.a.wen; din_a := vrfy_out.bram.a.din;
                if vrfy_out.mode_select_l1 = "10" then
                    addr_b := to_integer(unsigned(hmsg_out.bram.addr)); wen_b := hmsg_out.bram.wen; din_b := hmsg_out.bram.din;
                else
                    addr_b := to_integer(unsigned(vrfy_out.bram.b.addr)); wen_b := vrfy_out.bram.b.wen; din_b := vrfy_out.bram.b.din;
                end if;
            end if;

            if wen_a = '1' then bram_memory(addr_a) <= din_a; end if;
            if wen_b = '1' then bram_memory(addr_b) <= din_b; end if;
            
            bram_dout_a_reg <= bram_memory(addr_a);
            bram_dout_b_reg <= bram_memory(addr_b);
        end if;
    end process;

    -- Secuencia de Ejecución
   -- Secuencia de Ejecución
    process
    begin
        reset <= '1';
        wait for 50 ns; 
        wait until rising_edge(clk);
        reset <= '0'; 
        wait for 50 ns;
        
        report "===========================================================" severity note;
        report "=== INICIANDO PRUEBA KAT (KNOWN ANSWER TEST) DEFINITIVA ===" severity note;
        report "===========================================================" severity note;
        
        wait until rising_edge(clk);
        
        -- NUEVO COMPORTAMIENTO TIPO "HOST": Mantenemos el enable ALTO
        tb_enable <= '1'; 
        
        -- Esperamos a que el acelerador termine su orquestación
        wait until vrfy_out.done = '1';
        
        report " " severity note;
        report "=== VERIFICACION FINALIZADA ===" severity note;
        
        -- Leemos el resultado MIENTRAS el done está arriba
        if vrfy_out.valid = '1' then
            report "    [PASS] FIRMA VALIDA. LAS RAICES SON IGUALES" severity note;
        else
            report "    [FAIL] RESULTADO DE LA FIRMA: VALID = 0 (Las raices no coinciden)" severity error;
        end if;
        report "===========================================================" severity note;
        
        -- El procesador ha leído el resultado y da acuse de recibo bajando el enable
        wait for clk_period;
        tb_enable <= '0';
        
        -- Comprobamos que el sistema obedece, limpia el valid y vuelve a reposo
        wait for 4 * clk_period;
        if vrfy_out.valid = '0' and vrfy_out.done = '0' then
             report "    [INFO] Sistema reseteado y en reposo correctamente." severity note;
        end if;
        
        wait;
    end process;

end Behavioral;