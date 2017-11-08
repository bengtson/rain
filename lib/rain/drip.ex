defmodule Rain.Drip do

  def send_drip do
    drip_message =
      %{
        type: "mp3",
        filename: "/home/pi/Water Drop Sound Low.mp3"
      }

    send_packet drip_message
  end

  defp send_packet map do
    with  {:ok, packet} <- Poison.encode(map),
          {:ok, socket} <- :gen_tcp.connect('10.0.1.212', 7100,
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
