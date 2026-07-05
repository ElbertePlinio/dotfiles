return {
  {
    "mfussenegger/nvim-dap",
    config = function() end,
  },
  {
    "nvim-flutter/flutter-tools.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim",
      "mfussenegger/nvim-dap",
    },
    opts = {
      ui = {
        border = "rounded",
        notification_style = "native",
      },
      decorations = {
        statusline = {
          app_version = true,
          device = true,
          project_config = true,
        },
      },
      debugger = {
        enabled = true,
        exception_breakpoints = {},
        evaluate_to_string_in_debug_views = true,
      },
      fvm = true,
      widget_guides = {
        enabled = true,
      },
      closing_tags = {
        enabled = true,
      },
      dev_log = {
        enabled = true,
        open_cmd = "15split",
        focus_on_open = false,
      },
      dev_tools = {
        autostart = false,
        auto_open_browser = false,
      },
      outline = {
        open_cmd = "30vnew",
        auto_open = false,
      },
      lsp = {
        settings = {
          showTodos = true,
          completeFunctionCalls = true,
          renameFilesWithClasses = "prompt",
          enableSnippets = true,
          updateImportsOnRename = true,
        },
      },
    },
    config = function(_, opts)
      require("flutter-tools").setup(opts)

      vim.keymap.set("n", "<F5>", "<cmd>FlutterRun<cr>", { desc = "Flutter Run/Debug" })
      vim.keymap.set("n", "<S-F5>", "<cmd>FlutterQuit<cr>", { desc = "Flutter Stop" })
      vim.keymap.set("n", "<F6>", "<cmd>FlutterReload<cr>", { desc = "Flutter Hot Reload" })
      vim.keymap.set("n", "<S-F6>", "<cmd>FlutterRestart<cr>", { desc = "Flutter Hot Restart" })
      vim.keymap.set("n", "<leader>fd", "<cmd>FlutterDevices<cr>", { desc = "Flutter Devices" })
      vim.keymap.set("n", "<leader>fe", "<cmd>FlutterEmulators<cr>", { desc = "Flutter Emulators" })
      vim.keymap.set("n", "<leader>fl", "<cmd>FlutterLogToggle<cr>", { desc = "Flutter Logs" })
      vim.keymap.set("n", "<leader>ft", "<cmd>FlutterDevTools<cr>", { desc = "Flutter DevTools" })
      vim.keymap.set("n", "<leader>fT", "<cmd>FlutterOpenDevTools<cr>", { desc = "Flutter Open DevTools" })
      vim.keymap.set("n", "<leader>fi", "<cmd>FlutterInspectWidget<cr>", { desc = "Flutter Inspect Widget" })
      vim.keymap.set("n", "<leader>fo", "<cmd>FlutterOutlineToggle<cr>", { desc = "Flutter Outline" })

      local group = vim.api.nvim_create_augroup("FlutterHotReloadOnSave", { clear = true })
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = "*.dart",
        callback = function(event)
          local dir = vim.fs.dirname(event.file)
          if not dir then
            return
          end

          local pubspec = vim.fs.find("pubspec.yaml", { path = dir, upward = true })[1]
          if not pubspec then
            return
          end

          vim.schedule(function()
            pcall(vim.cmd, "FlutterReload")
          end)
        end,
      })
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
    },
    keys = {
      {
        "<leader>du",
        function()
          require("dapui").toggle()
        end,
        desc = "Toggle DAP UI",
      },
    },
    opts = {},
    config = function(_, opts)
      local dap = require("dap")
      local dapui = require("dapui")
      dapui.setup(opts)
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },
}
