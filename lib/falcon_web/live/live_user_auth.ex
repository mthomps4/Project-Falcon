defmodule FalconWeb.LiveUserAuth do
  @moduledoc """
  LiveView on_mount hook that assigns current_scope to the socket.
  """

  use FalconWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component

  alias Falcon.Accounts
  alias Falcon.Accounts.Scope

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = assign_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/users/log-in")}
    end
  end

  defp assign_current_scope(socket, session) do
    case session["user_token"] do
      nil ->
        assign(socket, :current_scope, Scope.for_user(nil))

      token ->
        case Accounts.get_user_by_session_token(token) do
          {user, _inserted_at} ->
            assign(socket, :current_scope, Scope.for_user(user))

          nil ->
            assign(socket, :current_scope, Scope.for_user(nil))
        end
    end
  end
end
