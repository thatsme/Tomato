defmodule TomatoWeb.Router do
  @moduledoc false
  use TomatoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TomatoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TomatoWeb do
    pipe_through :browser

    live_session :default, layout: {TomatoWeb.Layouts, :live} do
      live "/", GraphLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TomatoWeb do
  #   pipe_through :api
  # end
end
