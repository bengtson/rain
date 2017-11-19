defmodule Rain.Status do
  @moduledoc """
  Provides the functionality needed to send status packets to the Tack Status
  Server. Status and useful metrics are sent periodically.
  Things to fix:

    - Host and Port are not used from the configuration file.
  """
  use GenServer

  defmodule Status do
    defstruct [ :name, :icon, :status, :state, :link, :hover, :metrics, :text ]
  end

  defmodule Metric do
    defstruct [ :name, :value ]
  end

  @millis_in_day 60*60*24*1000

  # --------- GenServer Startup Functions

  @doc """
  Starts the GenServer. This of course calls init with the :ok parameter.
  """
  def start_link do
    {:ok, _} = GenServer.start_link(__MODULE__, :ok, [name: StatusServer])
  end

  @doc """
  Read the rain data file and generate the list of rain gauge tips. This
  is held in the state as tips. tip_inches is amount of rain for each tip.
  """
  def init (:ok) do
    [host: host, port: port, start: _start] = Application.fetch_env!(:rain, :status_server)
    start()
    datetime = Timex.now("America/Chicago")
    {:ok, %{parms: %{host: host, port: port, started: datetime}, server: %{}, client: %{}, update_flag: :true, status: nil, day: nil}}
  end

  def start do
    spawn(__MODULE__,:update_tick,[])
  end

  def request_update do
    IO.inspect {:setting_update_flag}
    GenServer.call StatusServer, :set_update_flag
  end

  def update_status do
    GenServer.call StatusServer, :update_status
  end

  def handle_call(:update_status, _from, state) do
    IO.inspect {:checking_status}
    day = Timex.local().day
    status =
      if state.update_flag || (state.day != day)
        do
          generate_status()
        else
          state.status
      end
    send_packet status
    state =
      %{ state |
        status: status,
        update_flag: false,
        day: day
      }
    {:reply, :ok, state}
  end

  def handle_call(:set_update_flag, _from, state) do
    state = %{ state | update_flag: true}
    {:reply, :ok, state}
  end

  #------------ Tack Status
  def update_tick do
    Process.sleep(10000)
    update_status()
    update_tick()
  end

  def generate_status do

    IO.inspect {:generating_status}

    datetime = Timex.local()
    yearstart = Timex.set(datetime, [month: 1, day: 1]) |> Timex.beginning_of_day
    days = Timex.diff(datetime |> Timex.beginning_of_day,yearstart,:days) + 1

    today = get_rain_for_period datetime, 0, 1
    yesterday = get_rain_for_period datetime, -1, 1
    last7days = get_rain_for_period datetime, -7, 7
    last30days = get_rain_for_period datetime, -30, 30
    ytd = get_rain_for_period yearstart, 0, days

    {state, message, rate} = current_conditions()

    metrics =
      [
        %Metric{name: "Today", value: "#{today} in"},
        %Metric{name: "Rate", value: "#{rate} in/hr"},
        %Metric{name: "------------", value: ""},
        %Metric{name: "Yesterday", value: "#{yesterday} in"},
        %Metric{name: "Last 7 Days", value: "#{last7days} in"},
        %Metric{name: "Last 30 Days", value: "#{last30days} in"},
        %Metric{name: "Year to Date", value: "#{ytd} in"},
      ]

    stat = %Status{
      name: "Rain Gauge",
      icon: get_icon("priv/images/raingauge.png"),
      status: message,
      metrics: metrics,
      state: state,
      link: "http://10.0.1.202:4401"
    }

    stat
  end

  defp send_packet stat do
    IO.inspect {:sending_packet}
    with  {:ok, packet} <- Poison.encode(stat),
          {:ok, socket} <- :gen_tcp.connect('10.0.1.202', 21200,
                           [:binary, active: false])
    do
            :gen_tcp.send(socket, packet)
            :gen_tcp.close(socket)
            :ok
    else
      _ ->  :ok
    end
  end

  defp get_icon path do
    {:ok, icon} = File.read path
    icon = Base.encode64 icon
    icon
  end

  defp get_rain_for_period datetime, days_shift, days do
    earliest = 1000 * (datetime |> Timex.beginning_of_day |> Timex.to_unix)
    earliest = earliest + @millis_in_day * days_shift
    latest = earliest + @millis_in_day * days - 1
    tips = Rain.Service.get_tip_count_in_range {earliest, latest}
    _inches = :io_lib.format("~5.2f",[tips/100.0])
  end

  # Determines the current conditions.
  # Looks at the last 10 tips and how quickly they came. More tips in less
  # time determines the level of rain. 10 tips in 1 minute (6.0" / hr) is
  # cats and dogs. 2 tips in 1 minutes is a light rain 0.6" / hr.
  # Rate is determined by the time between the two most recent tips, if they
  # exist.
  @rate_window_minutes 3
  defp current_conditions do

    now_millis = 1000 * (Timex.local |> Timex.to_unix)
    current =
      Rain.Service.get_tips
      |> Enum.take(10)
      |> Enum.map(fn m -> now_millis - m end)
      |> Enum.with_index
      |> Enum.map(fn {m,i} -> {i,m} end)
      |> Enum.into(%{})

    # Calculate rate over last 3 minutes.
    latest = 1000 * (Timex.local |> Timex.to_unix)
    earliest = latest - @rate_window_minutes * 60 * 1000
    tips = Rain.Service.get_tip_count_in_range {earliest, latest}
    rate = 0.01 * tips * 60.0 / @rate_window_minutes

    {state, message} =
      cond do
        current[9] < 60_000 -> {:alarm, "Cats and Dogs"}    # 6.0 in / hr
        current[5] < 60_000 -> {:warning, "Heaving Rain"}   # 3.0 in / hr
        current[2] < 60_000 -> {:warning, "Raining"}        # 1.2 in / hr
        current[1] < 300_000 -> {:nominal, "Rain"}          # 0.24 in / hr
        current[1] < 600_000 -> {:nominal, "Light Rain"}    # 0.12 in / hr
        true -> {:nominal, "Not Raining"}
      end

    {state, message, :io_lib.format("~5.2f",[rate])}
  end

end
