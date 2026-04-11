defmodule Tomato.Edge do
  @moduledoc """
  A directed dependency between two nodes on the same floor.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          from: String.t(),
          to: String.t()
        }

  @derive Jason.Encoder
  @enforce_keys [:id, :from, :to]
  defstruct [:id, :from, :to]

  @spec new(String.t(), String.t()) :: t()
  def new(from, to) do
    %__MODULE__{
      id: UUID.uuid4(),
      from: from,
      to: to
    }
  end
end
