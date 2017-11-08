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
    {:ok, %{tips: tips, tip_inches: tip_inches}}
  end

# --------- Client APIs

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

end
