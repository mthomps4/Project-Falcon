defmodule FalconWeb.UserSessionHTML do
  use FalconWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:falcon, Falcon.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
