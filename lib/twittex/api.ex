defmodule Twittex.API do
  @moduledoc """
  Twitter API wrapper.

  Provides convenience functions for working with Twitter's RESTful API. You can
  use `head/3`, `get/3`, `post/4`, and others using a relative url pointing to
  the API endpoint.

  For example:

      iex> API.get! "/search/tweets.json?q=%23myelixirstatus"
      %HTTPoison.Response{}

  ## Authentication

  Twittex supports following *OAuth* authentication methods:

  * [Application-only] authentication.
  * [xAuth] authentication with user credentials.

  To request an access token with one of the method listed above. See `get_token/1`
  and `get_token/3`. Here's, a brief example:

      iex> token = API.get_token!
      %OAuth2.AccessToken{}

  Under the hood, the `Twittex.API` module uses `HTTPoison.Base` and overrides the
  `request/5` method to pass the authentication headers along the request.

  Twitter requires clients accessing their API to be authenticated. This means
  that you must provide the authentication token for each and every request.

  This can be done by passing the *OAuth* token as `:auth` option to the request function:

      iex> API.get! "/statuses/home_timeline.json", [], auth: token
      %HTTPoison.Response{}

  [xAuth]: https://dev.twitter.com/oauth/xauth
  [Application-only]: https://dev.twitter.com/oauth/application-only
  """

  use HTTPoison.Base

  alias OAuther, as: OAuth1

  @api_version 1.1
  @api_url "https://api.twitter.com"

  @api_key Application.get_env(:twittex, :consumer_key)
  @api_secret Application.get_env(:twittex, :consumer_secret)

  @doc """
  Request a user specific (*xAuth*) authentication token.

  [xAuth] provides a way for applications to exchange a username and password
  for an *OAuth* access token. It is required when accessing APIs that require user context.

  Returns `{:ok, token}` if the request is successful, `{:error, reason}` otherwise.

  [xAuth]: https://dev.twitter.com/oauth/xauth
  """
  @spec get_token(String.t, String.t, Keyword.t) :: {:ok, OAuth1.Credentials.t} | {:error, HTTPoison.Error.t}
  def get_token(username, password, options \\ []) do
    # build basic OAuth1 credentials
    credentials = OAuth1.credentials([
      consumer_key: @api_key,
      consumer_secret: @api_secret
    ])

    # build authentication header and request parameters
    access_token_url = @api_url <> "/oauth/access_token"
    {header, params} = OAuth1.sign("post", access_token_url, [
      {"x_auth_mode", "client_auth"},
      {"x_auth_username", username},
      {"x_auth_password", password},
    ], credentials) |> OAuth1.header

    # request single-user token
    case post(access_token_url, {:form, params}, [header], options) do
      {:ok, response} ->
        {:ok, struct(credentials, (for {"oauth_" <> key, val} <- URI.decode_query(response.body), do: {String.to_atom(key), val}))}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Same as `get_token/3` but raises `HTTPoison.Error` if an error occurs during the
  request.
  """
  @spec get_token!(String.t, String.t, Keyword.t) :: OAuth1.Credentials.t
  def get_token!(username, password, options \\ []) do
    case get_token(username, password, options) do
      {:ok, token} -> token
      {:error, error} -> raise error
    end
  end

  @doc """
  Request an *Application-only* authentication token.

  With [Application-only] authentication you don’t have the context of an
  authenticated user and this means that accessing APIs that require user context, will not work.

  Returns `{:ok, token}` if the request is successful, `{:error, reason}` otherwise.

  [Application-only]: https://dev.twitter.com/oauth/application-only
  """
  @spec get_token(Keyword.t) :: {:ok, OAuth2.AccessToken.t} | {:error, OAuth2.Error.t}
  def get_token(options \\ []) do
    # build basic OAuth2 client credentials
    client = OAuth2.Client.new([
      strategy: OAuth2.Strategy.ClientCredentials,
      client_id: @api_key,
      client_secret: @api_secret,
      site: @api_url,
      token_url: "/oauth2/token",
    ])

    # request bearer token
    case OAuth2.Client.get_token(client, [], [], options) do
      {:ok, %OAuth2.Client{token: token}} ->
        token =
          token
          |> Map.fetch!(:access_token)
          |> OAuth2.AccessToken.new()
        {:ok, token}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Same as `get_token/1` but raises `OAuth2.Error` if an error occurs during the
  request.
  """
  @spec get_token!(Keyword.t) :: OAuth2.AccessToken.t
  def get_token!(options \\ []) do
    case get_token(options) do
      {:ok, token} -> token
      {:error, error} -> raise error
    end
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    # make url absolute
    url =
      unless URI.parse(url).scheme do
        @api_url <> "/#{@api_version}" <> url
      else
        url
      end

    # if available, inject authentication header
    {headers, options} =
      if Keyword.has_key?(options, :auth) do
        {auth, options} = Keyword.pop(options, :auth)
        oauth =
          case auth do
            %OAuth2.AccessToken{} = token ->
              {"Authorization", "#{token.token_type} #{token.access_token}"}
            %OAuth1.Credentials{} = credentials ->
              OAuth1.sign(to_string(method), url, [], credentials) |> OAuth1.header |> elem(0)
          end
        {[oauth|headers], options}
      else
        {headers, options}
      end

    # call HTTPoison.request/5
    case super(method, url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: status_code, headers: headers, body: body} = response} ->
        body = process_response_body(body, headers)
        if status_code in 200..299 do
          {:ok, struct(response, body: body)}
        else
          case body do
            %{"errors" => [%{"message" => reason}]} ->
              {:error, %HTTPoison.Error{reason: reason}}
            reason ->
              {:error, %HTTPoison.Error{reason: reason}}
          end
        end
      {:ok, %HTTPoison.AsyncResponse{} = async_response} ->
        {:ok, async_response}
      {:error, error} ->
        {:error, error}
    end
  end

  defp process_response_body(body, headers) do
    import OAuth2.Util, only: [content_type: 1]
    case content_type(headers) do
      "application/json" ->
        Poison.decode!(body)
      "text/javascript" ->
        Poison.decode!(body)
      "application/x-www-form-urlencoded" ->
        URI.decode_query(body)
      _ ->
        body
    end
  end
end
