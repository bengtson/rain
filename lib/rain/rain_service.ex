defmodule Rain.Service do
  use GenServer
  require Logger

  @moduledoc """
  This server handles the data from the rain gauge. Initially, it interacts
  with the Java RainGauge program running on the iMac. It should later be
  modified to accept data directly from the rain gauge and be the primary
  server for all rain data collected.

  The following functions are performed by the Rain server:

    - Retrieve the rain tip data from the iMac Rain Gauge server and convert
      it to the new file format. Write the new file and generate internal
      list of all data.
    - Listen for tips on specified UDP port and add to the internal table but
      also append to the local data file.
    - Retrieve data based on a specified date range.
    - Retrieve data based on a specified range from now.

  """

# --------- GenServer Startup Functions

  @doc """
  Starts the GenServer.
  """
  def start_link do
    IO.inspect {:starting}
    {:ok, _} = GenServer.start_link(__MODULE__, :ok, [name: RainService, timeout: 20000])
  end

  @doc """
  Read the rain data file and generate the list of rain gauge tips. This
  is held in the state as tips. tip_inches is amount of rain for each tip.
  """
  def init (:ok) do
    tip_inches = Application.fetch_env!(:rain, :rain_parms)[:tip_inches]
    tips =
      read_tip_log_file()
#      |> write_rain_data
    port = Application.fetch_env!(:rain, :rain_parms)[:port]
    tcp_start port

    {:ok, %{tips: tips, tip_inches: tip_inches}}
  end

# --------- Client APIs

  @doc """
  Returns the list tips.
  """
  def get_tips do
    GenServer.call RainService, :get_tips
  end

  @doc """
  Returns a list of the tips in the range specified. These are sorted from most
  recent to earliest.
  """
  def get_tips_in_range {earliest, latest} do
    GenServer.call RainService, {:tips_in_range, earliest, latest}
  end

  @doc """
  Returns the earliest and latest tips.
  """
  def get_tip_data_range do
    GenServer.call RainService, :tip_data_range
  end

  @doc """
  Returns the total number of tips in the range provided. The range
  specification is inclusive.
  """
  def get_tip_count_in_range {earliest, latest} do
    GenServer.call RainService, {:tip_count_in_range, earliest, latest}
  end

  @doc """
  Returns the number of tips for the date provided.
  """
  def tip_count_for_date date do
    first = date |> Timex.to_datetime("America/Chicago") |> Timex.beginning_of_day
    last = first |> Timex.end_of_day
    first = (first |> Timex.to_unix) * 1000
    last = (last |> Timex.to_unix) * 1000
    get_tip_count_in_range {first, last}
  end

# --------- GenServer Callbacks

  def handle_call(:get_tips, _from, state) do
    {:reply, state.tips, state}
  end

  @doc """
  Returns the first and last tips in the data file.
  """
  def handle_call(:tip_data_range, _from, state) do
    earliest = List.last state[:tips]
    latest = List.first state[:tips]
    {:reply, {earliest, latest}, state}
  end

  @doc """
  Returns the tips in the specified range.
  """
  def handle_call({:tips_in_range, earliest, latest}, _from, state) do
    tips =
      state[:tips]
      |> Enum.filter(fn(x) -> x >= earliest and x <= latest end)
    {:reply, tips, state}
  end

  @doc """
  Returns the total number of tips in the specified range.
  """
  def handle_call({:tip_count_in_range, earliest, latest}, _from, state) do
    count =
      state[:tips]
      |> Enum.filter(fn(x) -> x >= earliest and x <= latest end)
      |> Enum.count
    {:reply, count, state}
  end

  def handle_call({:add_tips, tips}, _from, state) do
    new_tips = tips ++ state.tips
    state = %{ state | tips: new_tips}
    append_tips_to_file tips
    Rain.Status.set_update_flag
    Rain.Drip.send_drip()
    {:reply, :ok, state}
  end

# --------- Private Support Functions

  # Reads the data from the old format colletor file and generates data for
  # the new format file.
  defp read_tip_log_file do
    filepath = Application.fetch_env!(:rain, :rain_parms)[:tip_file]
    File.read!(filepath)
    |> String.split("\n")
    |> Enum.filter(fn l -> String.length(l) != 0 end)
    |> Enum.filter(fn l -> not String.starts_with?(l, "\#") end)
    |> Enum.map(&(String.split(&1,",")))
    |> List.flatten
    |> Enum.map(&(String.split(&1,"//")))
    |> List.flatten
    |> Enum.reject(fn(x) -> x == "rain:" end)
    |> Enum.map(fn(x) -> {n,_} = Integer.parse(x); n end)
    |> Enum.sort
    |> Enum.reverse
  end

  # Writes the tip data to the new format rain file.
  defp write_rain_data tips do
    write_data =
      tips
      |> Enum.reverse
      |> Enum.map(&Integer.to_string/1)
      |> Enum.chunk(10,10,[])
      |> Enum.map(&(Enum.join(&1," ")))
      |> Enum.join("\n")
    write_data = write_data <> "\n"

    filepath = Application.fetch_env!(:meteorologics, :rain_parms)[:rain_data_file]
    :ok = File.write filepath, write_data
    tips
  end

  # ---------- TCP server

  defp tcp_start port do
    socket = start_controller_messaging(port)
    spawn(Rain.Service, :message_accept, [socket])
  end

  def start_controller_messaging port do
    {:ok, socket} = :gen_tcp.listen(port,
                    [:binary, active: false, reuseaddr: true])
    socket
  end

  def message_accept socket do
    IO.inspect {:accept}
    {:ok, client} = :gen_tcp.accept(socket)
    packet = read_packet_data client, ""
    tips = packet_to_tips packet
    GenServer.call(RainService, {:add_tips, tips})
    message_accept socket
  end

  def packet_to_tips packet do
    packet
    |> String.split("\n")
    |> Enum.filter(fn l -> String.length(l) != 0 end)
    |> Enum.filter(fn l -> not String.starts_with?(l, "\#") end)
    |> Enum.map(&(String.split(&1,",")))
    |> List.flatten
    |> Enum.map(&(String.split(&1,"//")))
    |> List.flatten
    |> Enum.reject(fn(x) -> x == "rain:" end)
    |> Enum.map(fn(x) -> {n,_} = Integer.parse(x); n end)
    |> Enum.sort
    |> Enum.reverse
  end

  # Added this since Elixir was first receiving just the opening
  # `{` from the controller. This code reads until the controller
  # closes the channel.
  defp read_packet_data socket, packet do
    resp = :gen_tcp.recv(socket, 0, 10000)
    case resp do
      {:ok, data} ->
        packet = packet <> data
        read_packet_data(socket, packet)
      _ ->
        packet
    end
  end

  def append_tips_to_file tips do
    tlist =
      tips
      |> Enum.map(fn t -> "#{t}" end)
      |> Enum.join(",")
    addendum = "rain://" <> tlist <> "\n"
    filepath = Application.fetch_env!(:rain, :rain_parms)[:tip_file]
    File.write!(filepath, addendum, [:append])
  end


  def test_tip do
    packet = "rain://1510180927000,1510180951000,1510180959000\n"
    IO.inspect {:sending_packet}
    with  {:ok, socket} <- :gen_tcp.connect('localhost', 7575,
                           [:binary, active: false])
    do
            :gen_tcp.send(socket, packet)
            :gen_tcp.close(socket)
            :ok
    else
      _ ->  :ok
    end

  end


end
