defmodule Tomato.OODN do
  @moduledoc """
  Out-Of-DAG Node — ambient key-value context available to any template function.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          value: any()
        }

  @derive Jason.Encoder
  @enforce_keys [:id, :key, :value]
  defstruct [:id, :key, :value]

  @spec new(String.t(), any()) :: t()
  def new(key, value) do
    %__MODULE__{
      id: UUID.uuid4(),
      key: key,
      value: value
    }
  end
end
