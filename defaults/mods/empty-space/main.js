import { View, div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { theme } from "herdr";

export default class EmptySpace extends View {
  render() {
    const t = theme();
    return v_flex().size_full().items_center().justify_center().bg(t.background)
      .child(div().text_size(13).text_color(t.dim).child("Space đang trống · Bật Manager hoặc thêm agent để bắt đầu"));
  }
}
