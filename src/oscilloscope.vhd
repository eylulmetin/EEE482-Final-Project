library ieee;
use ieee.std_logic_1164.all;

entity oscilloscope is
    generic (
        ADC_DATA_WIDTH : integer;
        MAX_UPSAMPLE : integer;
        MAX_DOWNSAMPLE : integer
    );
    port (
        clock : in std_logic;
        reset : in std_logic;
        horizontal_scale : in std_logic_vector(31 downto 0); -- us/div
        vertical_scale : in std_logic_vector(31 downto 0); -- mV/div
        upsample : in integer range 0 to MAX_UPSAMPLE; -- upsampling rate is 2 ** upsample
        downsample : in integer range 0 to MAX_DOWNSAMPLE; -- downsampling rate is 2 ** downsample
        interpolation_enable : in std_logic;
        trigger_type : in std_logic; -- '1' for rising edge, '0' for falling edge
        trigger_ref : in std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);
        trigger_correction_enable : in std_logic;
        adc_data : in std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);
        adc_sample : in std_logic;
        pixel_clock : out std_logic;
        hsync, vsync : out std_logic;
        r, g, b : out std_logic_vector(7 downto 0)
    );
end oscilloscope;

architecture arch of oscilloscope is

    component data_acquisition is
        generic (
            ADDR_WIDTH : integer;
            DATA_WIDTH : integer;
            MAX_UPSAMPLE : integer;
            MAX_DOWNSAMPLE : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            -- ADC
            adc_data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            adc_sample : in std_logic;
            -- trigger signal
            trigger : in std_logic;
            -- configuration
            upsample : in integer range 0 to MAX_UPSAMPLE; -- upsampling rate is 2 ** upsample
            downsample : in integer range 0 to MAX_DOWNSAMPLE; -- downsampling rate is 2 ** downsample
            -- write bus
            write_bus_grant : in std_logic;
            write_bus_acquire : out std_logic;
            write_address : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
            write_en : out std_logic;
            write_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    component triggering is
        generic (
            DATA_WIDTH : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            adc_data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            adc_sample : in std_logic;
            trigger_type : in std_logic; -- '1' for rising edge, '0' for falling edge
            trigger_ref : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            trigger : out std_logic;
            trigger_frequency : out std_logic_vector(31 downto 0) -- Hz
        );
    end component;

    component sinc_interpolation is
        generic (
            READ_ADDR_WIDTH : integer;
            WRITE_ADDR_WIDTH : integer;
            DATA_WIDTH : integer range 8 to 12;
            MAX_UPSAMPLE : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            upsample : in integer range 0 to MAX_UPSAMPLE; -- upsampling rate is 2 ** upsample
            -- read bus
            read_bus_grant : in std_logic;
            read_data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            read_bus_acquire : out std_logic;
            read_address : out std_logic_vector(READ_ADDR_WIDTH - 1 downto 0);
            -- write bus
            write_bus_grant : in std_logic;
            write_bus_acquire : out std_logic;
            write_address : out std_logic_vector(WRITE_ADDR_WIDTH - 1 downto 0);
            write_en : out std_logic;
            write_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    component trigger_correction is
        generic (
            READ_ADDR_WIDTH : integer;
            WRITE_ADDR_WIDTH : integer;
            DATA_WIDTH : integer;
            MAX_UPSAMPLE : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            enable : in std_logic;
            trigger_type : in std_logic; -- '1' for rising edge, '0' for falling edge
            trigger_ref : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            -- read bus
            read_bus_grant : in std_logic;
            read_data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            read_bus_acquire : out std_logic;
            read_address : out std_logic_vector(READ_ADDR_WIDTH - 1 downto 0);
            -- write bus
            write_bus_grant : in std_logic;
            write_bus_acquire : out std_logic;
            write_address : out std_logic_vector(WRITE_ADDR_WIDTH - 1 downto 0);
            write_en : out std_logic;
            write_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    component vga is
        generic (
            READ_ADDR_WIDTH : integer;
            READ_DATA_WIDTH : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            horizontal_scale : in std_logic_vector(31 downto 0); -- us/div
            vertical_scale : in std_logic_vector(31 downto 0); -- mV/div
            trigger_type : in std_logic; -- '1' for rising edge, '0' for falling edge
            trigger_level : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0); -- mV
            trigger_frequency : in std_logic_vector(31 downto 0); -- Hz
            voltage_pp : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0); -- mV
            voltage_avg : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0); -- mV
            voltage_max : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0); -- mV
            voltage_min : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0); -- mV
            mem_bus_grant : in std_logic;
            mem_data : in std_logic_vector(READ_DATA_WIDTH - 1 downto 0);
            mem_bus_acquire : out std_logic;
            mem_address : out std_logic_vector(READ_ADDR_WIDTH - 1 downto 0);
            pixel_clock : out std_logic;
            rgb : out std_logic_vector(23 downto 0);
            hsync : out std_logic;
            vsync : out std_logic
        );
    end component;

    component arbitrated_memory is
        generic (
            ADDR_WIDTH : integer;
            DATA_WIDTH : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            -- write bus
            write_bus_acquire : in std_logic;
            write_address : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
            write_en : in std_logic;
            write_data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            write_bus_grant : out std_logic;
            -- read bus
            read_bus_acquire : in std_logic;
            read_address : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
            read_bus_grant : out std_logic;
            read_data : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    component statistics is
        generic (
            DATA_WIDTH : integer;
            POP_SIZE_WIDTH : integer
        );
        port (
            clock : in std_logic;
            reset : in std_logic;
            enable : in std_logic;
            clear : in std_logic;
            data : in std_logic_vector(DATA_WIDTH - 1 downto 0);
            spread : out std_logic_vector(DATA_WIDTH - 1 downto 0);
            average : out std_logic_vector(DATA_WIDTH - 1 downto 0);
            maximum : out std_logic_vector(DATA_WIDTH - 1 downto 0);
            minimum : out std_logic_vector(DATA_WIDTH - 1 downto 0)
        );
    end component;

    constant PROCESSING_ADDR_WIDTH : integer := 10;
    constant VGA_ADDR_WIDTH : integer := 9;

    signal trigger : std_logic;
    signal trigger_frequency : std_logic_vector(31 downto 0);

    signal interpolation_upsample : integer range 0 to MAX_UPSAMPLE;

    signal write_bus_grant1 : std_logic;
    signal write_bus_acquire1 : std_logic;
    signal write_address1 : std_logic_vector(PROCESSING_ADDR_WIDTH - 1 downto 0);
    signal write_en1 : std_logic;
    signal write_data1 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal read_bus_acquire1 : std_logic;
    signal read_address1 : std_logic_vector(PROCESSING_ADDR_WIDTH - 1 downto 0);
    signal read_bus_grant1 : std_logic;
    signal read_data1 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal write_bus_grant2 : std_logic;
    signal write_bus_acquire2 : std_logic;
    signal write_address2 : std_logic_vector(PROCESSING_ADDR_WIDTH - 1 downto 0);
    signal write_en2 : std_logic;
    signal write_data2 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal read_bus_acquire2 : std_logic;
    signal read_address2 : std_logic_vector(PROCESSING_ADDR_WIDTH - 1 downto 0);
    signal read_bus_grant2 : std_logic;
    signal read_data2 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal write_bus_grant3 : std_logic;
    signal write_bus_grant3_delayed : std_logic;
    signal write_bus_acquire3 : std_logic;
    signal write_address3 : std_logic_vector(VGA_ADDR_WIDTH - 1 downto 0);
    signal write_en3 : std_logic;
    signal write_data3 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal read_bus_acquire3 : std_logic;
    signal read_address3 : std_logic_vector(VGA_ADDR_WIDTH - 1 downto 0);
    signal read_bus_grant3 : std_logic;
    signal read_data3 : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal measurements_enable : std_logic;
    signal measurements_clear : std_logic;

    signal voltage_pp : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);
    signal voltage_avg : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);
    signal voltage_max : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);
    signal voltage_min : std_logic_vector(ADC_DATA_WIDTH - 1 downto 0);

    signal rgb : std_logic_vector(23 downto 0);

begin

    data_acquisition_module : data_acquisition
        generic map (
            ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH,
            MAX_UPSAMPLE => MAX_UPSAMPLE,
            MAX_DOWNSAMPLE => MAX_DOWNSAMPLE
        )
        port map (
            clock => clock,
            reset => reset,
            adc_data => adc_data,
            adc_sample => adc_sample,
            trigger => trigger,
            upsample => upsample,
            downsample => downsample,
            write_bus_grant => write_bus_grant1,
            write_bus_acquire => write_bus_acquire1,
            write_address => write_address1,
            write_en => write_en1,
            write_data => write_data1
        );

    triggering_module : triggering
        generic map (
            DATA_WIDTH => ADC_DATA_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            adc_data => adc_data,
            adc_sample => adc_sample,
            trigger_type => trigger_type,
            trigger_ref => trigger_ref,
            trigger => trigger,
            trigger_frequency => trigger_frequency
        );

    acquisition_interpolation_memory : arbitrated_memory
        generic map (
            ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            write_bus_acquire => write_bus_acquire1,
            write_address => write_address1,
            write_en => write_en1,
            write_data => write_data1,
            write_bus_grant => write_bus_grant1,
            read_bus_acquire => read_bus_acquire1,
            read_address => read_address1,
            read_bus_grant => read_bus_grant1,
            read_data => read_data1
        );

    interpolation_upsample <= upsample when interpolation_enable = '1' else 0;

    interpolation_module : sinc_interpolation
        generic map (
            READ_ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            WRITE_ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH,
            MAX_UPSAMPLE => MAX_UPSAMPLE
        )
        port map (
            clock => clock,
            reset => reset,
            upsample => interpolation_upsample,
            read_bus_grant => read_bus_grant1,
            read_data => read_data1,
            read_bus_acquire => read_bus_acquire1,
            read_address => read_address1,
            write_bus_grant => write_bus_grant2,
            write_bus_acquire => write_bus_acquire2,
            write_address => write_address2,
            write_en => write_en2,
            write_data => write_data2
        );

    interpolation_correction_memory : arbitrated_memory
        generic map (
            ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            write_bus_acquire => write_bus_acquire2,
            write_address => write_address2,
            write_en => write_en2,
            write_data => write_data2,
            write_bus_grant => write_bus_grant2,
            read_bus_acquire => read_bus_acquire2,
            read_address => read_address2,
            read_bus_grant => read_bus_grant2,
            read_data => read_data2
        );

    trigger_correction_module : trigger_correction
        generic map (
            READ_ADDR_WIDTH => PROCESSING_ADDR_WIDTH,
            WRITE_ADDR_WIDTH => VGA_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH,
            MAX_UPSAMPLE => MAX_UPSAMPLE
        )
        port map (
            clock => clock,
            reset => reset,
            enable => trigger_correction_enable,
            trigger_type => trigger_type,
            trigger_ref => trigger_ref,
            read_bus_grant => read_bus_grant2,
            read_data => read_data2,
            read_bus_acquire => read_bus_acquire2,
            read_address => read_address2,
            write_bus_grant => write_bus_grant3,
            write_bus_acquire => write_bus_acquire3,
            write_address => write_address3,
            write_en => write_en3,
            write_data => write_data3
        );

    correction_vga_memory : arbitrated_memory
        generic map (
            ADDR_WIDTH => VGA_ADDR_WIDTH,
            DATA_WIDTH => ADC_DATA_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            write_bus_acquire => write_bus_acquire3,
            write_address => write_address3,
            write_en => write_en3,
            write_data => write_data3,
            write_bus_grant => write_bus_grant3,
            read_bus_acquire => read_bus_acquire3,
            read_address => read_address3,
            read_bus_grant => read_bus_grant3,
            read_data => read_data3
        );

    measurements_enable <= write_en3;
    measurements_clear <= write_bus_grant3 and (not write_bus_grant3_delayed);

    delay_register : process (clock, reset)
    begin
        if (reset = '1') then
            write_bus_grant3_delayed <= '0';
        elsif (rising_edge(clock)) then
            write_bus_grant3_delayed <= write_bus_grant3;
        end if;
    end process;

    voltage_measurements : statistics
        generic map (
            DATA_WIDTH => ADC_DATA_WIDTH,
            POP_SIZE_WIDTH => VGA_ADDR_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            enable => measurements_enable,
            clear => measurements_clear,
            data => write_data3,
            spread => voltage_pp,
            average => voltage_avg,
            maximum => voltage_max,
            minimum => voltage_min
        );

    vga_module : vga
        generic map (
            READ_ADDR_WIDTH => VGA_ADDR_WIDTH,
            READ_DATA_WIDTH => ADC_DATA_WIDTH
        )
        port map (
            clock => clock,
            reset => reset,
            horizontal_scale => horizontal_scale,
            vertical_scale => vertical_scale,
            trigger_type => trigger_type,
            trigger_level => trigger_ref,
            trigger_frequency => trigger_frequency,
            voltage_pp => voltage_pp,
            voltage_avg => voltage_avg,
            voltage_max => voltage_max,
            voltage_min => voltage_min,
            mem_bus_grant => read_bus_grant3,
            mem_data => read_data3,
            mem_bus_acquire => read_bus_acquire3,
            mem_address => read_address3,
            pixel_clock => pixel_clock,
            rgb => rgb,
            hsync => hsync,
            vsync => vsync
        );

    r <= rgb(23 downto 16);
    g <= rgb(15 downto 8);
    b <= rgb(7 downto 0);

end architecture;
