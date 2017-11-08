defmodule Rain.Metrics do
  @moduledoc """
  This module contains functions that provide general handling of the rain
  data.
  """

  @doc """
  Summary gives some useful information about the data in the rain file.
  """
  def summary do
    {earliest, latest} = Rain.Service.get_tip_data_range
    early_formatted =
      earliest
      |> tip_to_datetime
      |> Timex.format!("{0D}-{Mshort}-{YYYY} {0h12}:{m}:{s}")
    late_formatted =
      latest
      |> tip_to_datetime
      |> Timex.format!("{0D}-{Mshort}-{YYYY} {0h12}:{m}:{s}")
    IO.puts "Rain Data Range:\n  #{early_formatted}\n  #{late_formatted}"
    s = "Rain Data Range:\n  #{early_formatted}\n  #{late_formatted}" <> "\n"

    # Show total rain in file.
    tips = Rain.Service.get_tip_count_in_range {earliest, latest}
    inches = tips / 100.0
    IO.puts "Total Inches: #{inches}"
    s = s <> "Total Inches: #{inches}" <> "\n"

    # Show last 14 days.
    millis_in_day = 60*60*24*1000
    dt =
      Timex.local
      |> Timex.beginning_of_day
    0..13
    |> Enum.map(fn (d) -> {d,Timex.to_unix(Timex.shift(dt,days: -d))*1000} end)
    |> Enum.map(fn ({d,s}) -> {s,s+millis_in_day-1} end)
    |> Enum.map(fn ({s,e}) -> {s,Rain.Service.get_tip_count_in_range({s,e})} end)
    |> Enum.map(fn ({t,tips}) -> {Timex.local(Timex.from_unix(t,:milliseconds)),tips} end)
    |> Enum.map(fn ({dt,tips}) -> {Timex.format!(dt, "{WDshort} {0D} {Mshort}"),tips*0.01} end)
    |> Enum.scan({nil,nil,0},(fn ({dt,tips},{_,_,sum}) -> {dt,tips,sum+tips} end))
    |> Enum.map(fn ({dt,inches,acc}) -> {dt,:io_lib.format("~5.2f", [inches]),acc} end)
    |> Enum.map(fn ({dt,inches,acc}) -> {dt,inches,:io_lib.format("~5.2f", [acc])} end)
    |> Enum.map(fn ({dt,inches,acc}) -> IO.puts(" #{inches} (#{acc}): #{dt}") end)
#    |> IO.inspect

    # Find hardest rain in last 7 days
    latest =
      Timex.local()
      |> Timex.end_of_day
      |> Timex.to_unix
    earliest =
      Timex.local()
      |> Timex.shift(days: -6)
      |> Timex.beginning_of_day
      |> Timex.to_unix
    rate =
      Rain.Service.get_tips_in_range({earliest*1000, latest*1000})
      |> hardest_rain
#    rate = :io.format("~6.2f~n", [rate])
    IO.puts "Maximum Rate Last 7 Days: #{rate}\"/hr"

    s

  end

  @doc """
  Finds the set of tips that show the highest rain fall rate. NOTE: This
  will return 0 since there are duplicate tips in the data file at the seconds
  resolution.
  """
  def hardest_rain tips do
    millis =
      tips
      |> Enum.chunk(2,1)
      |> Enum.map(fn ([a,b]) -> a-b end)
      |> Enum.min(fn -> nil end)
    seconds = millis / 1000.0
    3600.0 / seconds * 0.01
  end

  @doc """
  Converts a tip timestamp to a DateTime structure.
  """
  def tip_to_datetime tip do
    Timex.local(Timex.from_unix(tip, :milliseconds))
  end

end
