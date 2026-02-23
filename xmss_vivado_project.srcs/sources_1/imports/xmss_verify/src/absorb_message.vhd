----------------------------------------------------------------------------------
-- Company: Ruhr-University Bochum / Chair for Security Engineering
-- Engineer: Jan Philipp Thoma
-- 
-- Modified: FLAWLESS 512-bit block formatter for standard SHA-256 (Deadlock Fixed)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.xmss_main_typedef.ALL;
use work.sha_comp.ALL;
use work.params.ALL;

entity absorb_message is
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           d     : in absorb_message_input_type;
           q     : out absorb_message_output_type);
end absorb_message;

architecture Behavioral of absorb_message is
    type state_type is (
        S_IDLE, 
        S_FETCH_LOW, 
        S_HASHING, 
        S_WAIT_SHA_MNEXT, 
        S_LOAD_HIGH
    );
    
    type reg_type is record 
        state : state_type;
        block512 : unsigned(511 downto 0);
        total_len : integer;
        remaining_len : integer;
        len_appended : std_logic;
        hash_enable : std_logic;
        shift_ctr : integer range 0 to 31; -- Rango ampliado para evitar error de simulador
    end record;
    
    type out_signals is record
        sha : sha_output_type;
    end record;
    
    signal modules : out_signals;
    signal r, r_in : reg_type;
    
    signal next_message : std_logic_vector(31 downto 0);
    signal next_enable  : std_logic;
    signal next_last    : std_logic;

begin

    sha256 : entity work.sha256
    port map(
        clk       => clk,
        reset     => reset,
        d.enable  => next_enable,
        d.halt    => d.halt,
        d.last    => next_last,
        d.message => next_message,
        q         => modules.sha
    );

    q.o <= modules.sha.hash;

    combinational : process (r, d, modules)
       variable v : reg_type;
    begin
       v := r;
       v.hash_enable := '0';
       q.mnext <= '0';
       q.done <= '0';
        
       case r.state is
           when S_IDLE =>
               if d.enable = '1' then
                   v.total_len := d.len;
                   v.remaining_len := d.len;
                   -- Cargamos la mitad superior (primeros 256 bits)
                   v.block512(511 downto 256) := unsigned(d.input);
                   v.len_appended := '0';
                   v.shift_ctr := 0;
                   
                   if d.len > 256 then
                       -- Pedimos los siguientes 256 bits para llenar el bloque
                       q.mnext <= '1';
                       v.state := S_FETCH_LOW;
                   else
                       -- El mensaje cabe en la mitad superior, aplicamos padding directamente
                       v.block512(255 downto 0) := (others => '0');
                       v.block512(511 - d.len) := '1';
                       
                       for i in 256 to 511 loop
                           if i < 511 - d.len then
                               v.block512(i) := '0';
                           end if;
                       end loop;
                       
                       if d.len <= 447 then
                           v.block512(63 downto 0) := to_unsigned(d.len, 64);
                           v.len_appended := '1';
                       end if;
                       
                       v.hash_enable := '1';
                       v.state := S_HASHING;
                   end if;
               end if;
               
           when S_FETCH_LOW =>
               -- Cargamos la mitad inferior (siguientes 256 bits)
               v.block512(255 downto 0) := unsigned(d.input);
               
               if r.remaining_len < 512 then
                   -- Padding en la mitad inferior
                   v.block512(511 - r.remaining_len) := '1';
                   
                   for i in 0 to 511 loop
                       if i < 511 - r.remaining_len then
                           v.block512(i) := '0';
                       end if;
                   end loop;
                   
                   if r.remaining_len <= 447 then
                       v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                       v.len_appended := '1';
                   end if;
               end if;
               
               v.hash_enable := '1';
               v.state := S_HASHING;
               
           when S_HASHING =>
               -- Alimentamos 16 palabras exactamente en 16 ciclos
               v.block512 := SHIFT_LEFT(r.block512, 32);
               v.shift_ctr := r.shift_ctr + 1;
               
               if r.shift_ctr = 15 then
                   v.state := S_WAIT_SHA_MNEXT;
                   v.remaining_len := r.remaining_len - 512;
               end if;
               
           when S_WAIT_SHA_MNEXT =>
               -- Sincronizamos con el núcleo SHA-256 (¡CORRECCIÓN DE DEADLOCK AQUÍ!)
               if r.len_appended = '1' then
                   -- Si ya enviamos el último bloque (last=1), sha256 nunca assertará mnext,
                   -- sino que assertará done al terminar sus rondas. Lo esperamos:
                   if modules.sha.done = '1' then
                       q.done <= '1';
                       v.state := S_IDLE;
                   end if;
               else
                   -- Si no hemos terminado, sha256 nos pedirá el siguiente bloque con mnext:
                   if modules.sha.mnext = '1' then
                       if r.remaining_len <= 0 then
                           -- Solo falta el bloque de Padding final (porque la longitud no cabía en el anterior)
                           v.block512 := (others => '0');
                           if r.remaining_len = 0 then
                               v.block512(511) := '1';
                           end if;
                           v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                           v.len_appended := '1';
                           v.shift_ctr := 0;
                           v.hash_enable := '1';
                           v.state := S_HASHING;
                       else
                           -- Faltan más datos de WOTS
                           q.mnext <= '1';
                           v.state := S_LOAD_HIGH;
                       end if;
                   end if;
               end if;
               
           when S_LOAD_HIGH =>
               v.block512(511 downto 256) := unsigned(d.input);
               v.shift_ctr := 0;
               
               if r.remaining_len > 256 then
                   q.mnext <= '1';
                   v.state := S_FETCH_LOW;
               else
                   v.block512(255 downto 0) := (others => '0');
                   v.block512(511 - r.remaining_len) := '1';
                   
                   for i in 256 to 511 loop
                       if i < 511 - r.remaining_len then
                           v.block512(i) := '0';
                       end if;
                   end loop;
                   
                   if r.remaining_len <= 447 then
                       v.block512(63 downto 0) := to_unsigned(r.total_len, 64);
                       v.len_appended := '1';
                   end if;
                   
                   v.hash_enable := '1';
                   v.state := S_HASHING;
               end if;

       end case;
       
       -- Sincronización Look-Ahead (Elimina retrasos de 1 ciclo)
       next_message <= std_logic_vector(v.block512(511 downto 480));
       next_enable  <= v.hash_enable;
       next_last    <= v.len_appended;
       
       r_in <= v;
    end process;
    
    sequential : process(clk)
    begin
       if rising_edge(clk) then
        if reset = '1' then
           r.state <= S_IDLE;
        elsif d.halt = '0' then
           r <= r_in;
        end if;
       end if;
    end process;
    
end Behavioral;