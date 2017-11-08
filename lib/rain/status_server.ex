defmodule Rain.Status do
  @moduledoc """
  Provides the functionality needed to send status packets to the Tack Status
  Server. Status and useful metrics are send periodically. Status provides
  warnings, read metrics, last read entry and next entries to read.

  Things to fix:

    - move the read list into the GenServer. Keep it there.
    - date in the structure is used as a flag and really should be in the
      GenServer.
    - I don't like the read_flag. Is there a better approach.
    - Host and Port are not used from the configuration file.
  """
  use GenServer

  defmodule Status do
    defstruct [ :name, :icon, :status, :state, :link, :hover, :metrics, :text, :date ]
  end

  defmodule Metric do
    defstruct [ :name, :value ]
  end

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
    {:ok, %{parms: %{host: host, port: port, started: datetime}, server: %{}, client: %{}, readings_flag: :true, status: nil, status_day: nil}}
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

  def set_readings_flag do
    GenServer.call StatusServer, :set_readings_flag
  end

  def get_readings_flag do
    GenServer.call StatusServer, :get_readings_flag
  end

  def handle_call(:get_readings_flag, _from, state) do
    flag = state.readings_flag
    state = %{state | readings_flag: :false}
    {:reply, flag, state}
  end

  def handle_call({:set_current_status, status}, _from, state) do
    state = %{ state | status: status}
    {:reply, :ok, state}
  end

  def handle_call(:get_current_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:set_readings_flag, _from, state) do
    state = %{ state | readings_flag: true}
    IO.inspect {:readings_flag, state.readings_flag}
    {:reply, :ok, state}
  end

  #------------ Tack Status
  def update_status do
    Process.sleep(10000)
    send_status()
    update_status()
  end

  def send_status do

    # Status can include 'raining/rate', precip today, yesterday, 7 days,
    # 30 days, ytd

    IO.inspect {:sending_status}

    metrics =
      [
        %Metric{name: "Rain", value: "0.01 in"}
      ]

    stat = %Status{
      name: "Rain Gauge",
      icon: get_icon("priv/images/raingauge.png"),
      status: "Service Running",
      metrics: metrics,
      state: :nominal,
      link: "http://10.0.1.202:4401",
      date: Timex.local()
    }

    send_packet stat
  end

  defp send_packet stat do
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

end
