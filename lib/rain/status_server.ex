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
    {:ok, %{parms: %{host: host, port: port, started: datetime}, server: %{}, client: %{}, update_flag: :true, status: nil, status_day: nil}}
  end

  def start do
    spawn(__MODULE__,:update_status,[])
  end

  def set_current_status status do
    GenServer.call StatusServer, {:set_current_status, status}
  end

  def get_current_status do
    GenServer.call StatusServer, :get_current_status
  end

  def clear_update_flag do
    GenServer.call StatusServer, :clear_update_flag
  end

  def set_update_flag do
    IO.inspect {:setting_update_flag}
    GenServer.call StatusServer, :set_update_flag
  end

  def get_update_flag do
    GenServer.call StatusServer, :get_update_flag
  end

  def handle_call({:set_current_status, status}, _from, state) do
    state = %{ state | status: status}
    {:reply, status, state}
  end

  def handle_call(:get_current_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:set_update_flag, _from, state) do
    state = %{ state | update_flag: true}
    {:reply, :ok, state}
  end

  def handle_call(:clear_update_flag, _from, state) do
    state = %{ state | update_flag: false}
    {:reply, :ok, state}
  end

  def handle_call(:get_update_flag, _from, state) do
    flag = state.update_flag
    {:reply, flag, state}
  end

  #------------ Tack Status
  def update_status do
    Process.sleep(10000)
    IO.inspect {:checking_status}
    if get_update_flag() do generate_status() end
    send_packet get_current_status()
    update_status()
  end

  def generate_status do

    IO.inspect {:generating_status}

    # Status can include 'raining/rate', precip today, yesterday, 7 days,
    # 30 days, ytd

#    r = Rain.Metrics.summary()
#    IO.inspect {:summary, r}
    datetime = Timex.local()
    yearstart = Timex.set(datetime, [month: 1, day: 1]) |> Timex.beginning_of_day
    days = Timex.diff(datetime |> Timex.beginning_of_day,yearstart,:days) + 1
#    IO.inspect {:day_of_year, days}
    today = get_rain_for_period datetime, 0, 1
    yesterday = get_rain_for_period datetime, -1, 1
    last7days = get_rain_for_period datetime, -7, 7
    last30days = get_rain_for_period datetime, -30, 30
    ytd = get_rain_for_period yearstart, 0, days

    {state, message, rate} = get_current_conditions()

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

    set_current_status stat
    clear_update_flag()
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

  defp get_current_conditions do
    latest = 1000 * (Timex.local |> Timex.to_unix)
    earliest = latest - 15 * 60 * 1000
    tips = Rain.Service.get_tip_count_in_range {earliest, latest}
    {state, message} =
      cond do
        tips == 0 -> {:nominal, "Not Raining"}
        tips > 100 -> {:alarm, "Cat and Dogs"}    # 4" / Hour
        tips > 50  -> {:warning, "Heavy Rain"}    # 2" / Hour
        tips > 10  -> {:warning, "Raining"}       # 0.4" / Hour
        true       -> {:nominal, "Light Rain"}
      end

    {state, message, :io_lib.format("~5.2f",[tips*4.0/100.0])}
  end

end
