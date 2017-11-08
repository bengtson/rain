defmodule Rain.Fix do
  @moduledoc """
  The Tack Java Rain Server was not capturing tips around Nov 2 through Nov 6
  2017. Data was taken from PWS KILEFFIN12 for those days.

  This program takes strange CSV data and generates tips to fill in the data
  on those days.
  """
  @rain_data_path "/Users/bengm0ra/Desktop/rain/"

  def fix do

    # Get list of files in the rain data directory.
    @rain_data_path
    |> File.ls!

    # Read each file raw data, split to strings and flatten.
    |> Enum.map(fn file -> File.read!(@rain_data_path <> file) end)
    |> Enum.map(fn s -> String.split(s, "\n") end)
    |> List.flatten

    # Filter out <br> lines, 0 length lines, headers.
    |> Enum.filter(fn s -> s != "<br>" end)
    |> Enum.filter(fn s -> String.length(s) > 0 end)
    |> Enum.filter(fn s -> not String.starts_with?(s,"Time") end)

    # Separate fields and grab date/time and accumulated precip.
    |> Enum.map(fn s -> String.split(s,",") end)
    |> Enum.map(fn [a,b,c,d,e,f,g,h,i,j,k,l,m | _] -> {a,m} end)

    # Convert date to timestamp.
    |> Enum.map(fn {d,t} -> {date_to_ts(d),t} end)

    # Chunk into overlapping pairs. Keep only ones with added precip.
    |> Enum.chunk(2,1)
    |> Enum.filter(fn [{t0, p0}, {t1, p1}] -> p0 != p1 end )
    |> Enum.filter(fn [{t0, p0}, {t1, p1}] -> p0 < p1 end )

    # Interpolate new timestamps based on time and incremental precip.
    |> Enum.map(&gen_fix_timestamp/1)
    |> List.flatten
    |> Enum.map(&write_tip/1)
  end

  def write_tip tip do
    IO.puts "rain://#{tip}"
  end

  def gen_fix_timestamp [{t0, p0}, {t1, p1}] do
    IO.inspect {t0, p0, t1, p1}
    {f0,_} = Float.parse(p0)
    {f1,_} = Float.parse(p1)
    i0 = Kernel.trunc(f0*100.0)
    i1 = Kernel.trunc(f1*100.0)
    t0 = t0
    t1 = t1
    [{t0, i1}, {t1, i1}]

    # y is the timestamp, x is the precip amount.
    slope = (t1-t0)/(i1-i0)
#    y = slope x + b
    b = t0 - slope * i0
    IO.inspect {:slope, slope, :b, b}

    i0..(i1-1)
    |> Enum.map(fn i -> trunc(i * slope + b) * 1000 end)

  end

  def date_to_ts date do
    Timex.parse!(date <> " America/Chicago", "{YYYY}-{0M}-{0D} {h24}:{m}:{s} {Zname}")
    |> Timex.to_unix
  end
end
