# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.EctoType.ActivityPub.ObjectValidators.MIMETest do
  use Pleroma.DataCase, async: true

  require Pleroma.Constants

  describe "mime_regex/0" do
    test "validates standard MIME types" do
      {:ok, mime_regex} = Regex.compile(Pleroma.Constants.mime_regex())

      valid_mime_types = [
        "text/plain",
        "text/html",
        "text/css",
        "text/javascript",
        "application/json",
        "application/xml",
        "application/pdf",
        "application/zip",
        "application/octet-stream",
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/svg+xml",
        "audio/mpeg",
        "audio/wav",
        "audio/ogg",
        "video/mp4",
        "video/webm",
        "video/ogg",
        "multipart/form-data",
        "message/rfc822"
      ]

      Enum.each(valid_mime_types, fn mime_type ->
        assert mime_type =~ mime_regex, "Expected #{mime_type} to match mime_regex"
      end)
    end

    test "validates MIME types with parameters" do
      {:ok, mime_regex} = Regex.compile(Pleroma.Constants.mime_regex())

      valid_mime_types_with_params = [
        "text/plain; charset=utf-8",
        "text/html; charset=iso-8859-1",
        "application/json; charset=utf-8",
        "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"",
        "application/activity+json",
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW",
        "message/rfc822; charset=utf-8"
      ]

      Enum.each(valid_mime_types_with_params, fn mime_type ->
        assert mime_type =~ mime_regex, "Expected #{mime_type} to match mime_regex"
      end)
    end

    test "validates custom/vendor MIME types" do
      {:ok, mime_regex} = Regex.compile(Pleroma.Constants.mime_regex())

      valid_custom_mime_types = [
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.apple.mpegurl",
        "application/x-custom-type",
        "x-application/x-custom-type",
        "x-custom/x-type"
      ]

      Enum.each(valid_custom_mime_types, fn mime_type ->
        assert mime_type =~ mime_regex, "Expected #{mime_type} to match mime_regex"
      end)
    end

    test "rejects invalid MIME types" do
      {:ok, mime_regex} = Regex.compile(Pleroma.Constants.mime_regex())

      invalid_mime_types = [
        # Missing slash
        "text",
        "application",
        "image",
        # Control characters
        "text/\x00plain",
        "text/\x1Fplain",
        # Invalid characters according to RFC 2045
        "text/plain ",
        "text/plain(",
        "text/plain)",
        "text/plain<",
        "text/plain>",
        "text/plain@",
        "text/plain,",
        "text/plain\\",
        "text/plain\"",
        "text/plain/",
        "text/plain[",
        "text/plain]",
        "text/plain?",
        "text/plain=",
        # Invalid format
        "text/plain/extra",
        # Empty parts
        "/plain",
        "text/"
      ]

      Enum.each(invalid_mime_types, fn mime_type ->
        refute mime_type =~ mime_regex, "Expected #{mime_type} to NOT match mime_regex"
      end)
    end

    test "handles edge cases" do
      {:ok, mime_regex} = Regex.compile(Pleroma.Constants.mime_regex())

      edge_cases = [
        # Single character types
        "a/b",
        "x/y",
        # Long but valid types
        "application/very-long-subtype-name-that-is-still-valid",
        # Parameters with spaces
        "text/plain; charset= utf-8",
        "text/plain; charset =utf-8",
        "text/plain; charset = utf-8",
        # Multiple parameters
        "text/plain; charset=utf-8; boundary=123",
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW; charset=utf-8"
      ]

      Enum.each(edge_cases, fn mime_type ->
        assert mime_type =~ mime_regex, "Expected #{mime_type} to match mime_regex"
      end)
    end
  end
end
