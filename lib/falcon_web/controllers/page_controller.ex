defmodule FalconWeb.PageController do
  use FalconWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
