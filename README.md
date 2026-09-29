# QuietGlyph

**QuietGlyph 立志成为 macOS 上最优雅的文本编辑器。**

从打开一份笔记，到整理上千行代码，编辑器都应该让人专注于文字本身。QuietGlyph 使用 AppKit、SwiftUI 和 NSTextView 构建，遵循 macOS 的窗口、菜单与键盘操作习惯，同时提供处理复杂文本所需的工具。

## 功能

- 多窗口与标签页、自动恢复、书签，以及多光标和矩形选区编辑。
- 语法高亮、代码折叠、词语补全、主题与快捷键设置。
- 文档及目录内查找替换，支持正则表达式和批量规则。
- 编码与换行格式转换、Markdown 预览，以及大文件和十六进制只读查看。
- 批量重命名、批量转码、文本统计和摘要计算。

## 开发

使用 Xcode 27 或更新版本打开 `QuietGlyph.xcodeproj`。应用最低支持 macOS 15，同时构建 Apple 芯片与 Intel 版本。

```sh
bash Scripts/build.sh Debug
bash Scripts/test.sh unit
```

运行 `bash Scripts/test.sh all` 可执行单元测试和界面测试；运行 `bash Scripts/package.sh` 可在本地生成 DMG。

## 许可

本项目采用 GNU GPL v3，详见 `LICENSE`。资源来源与署名见 `NOTICE`。
