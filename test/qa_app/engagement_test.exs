defmodule QaApp.EngagementTest do
  use QaApp.DataCase

  alias QaApp.Engagement
  alias QaApp.Events

  describe "create_question/3 character limit" do
    test "counts Asian text character by character" do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "asian-text",
          "title" => "Asian Text",
          "char_limit" => 5,
          "is_active" => true
        })

      # 4 graphemes, within a 5 character limit
      assert {:ok, _question} =
               Engagement.create_question(room, "session-1", %{"content" => "你好世界"})
    end

    test "rejects questions that exceed the character limit, including Asian text" do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "asian-text-over",
          "title" => "Asian Text Over",
          "char_limit" => 5,
          "is_active" => true
        })

      # 6 graphemes, over a 5 character limit
      assert {:error, changeset} =
               Engagement.create_question(room, "session-1", %{"content" => "你好世界啊啦"})

      assert "exceeds the limit of 5 characters (currently 6 characters)" in errors_on(changeset).content
    end

    test "counts each word as multiple characters instead of a single word" do
      {:ok, room} =
        Events.create_room(%{
          "slug" => "word-vs-char",
          "title" => "Word vs Char",
          "char_limit" => 19,
          "is_active" => true
        })

      # 10 words but only 19 characters: passes a character-based limit
      # even though it would exceed an equivalent word limit of 9.
      content = String.duplicate("a ", 9) <> "a"

      assert {:ok, _question} =
               Engagement.create_question(room, "session-1", %{"content" => content})
    end
  end
end
