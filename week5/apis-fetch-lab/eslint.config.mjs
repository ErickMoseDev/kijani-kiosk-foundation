import globals from "globals";
import pluginJs from "@eslint/js";

const customGlobals = {
  ...globals.browser,
  module: 'readonly',
};

export default [
  {
    languageOptions: { globals: customGlobals },
  },
  pluginJs.configs.recommended,
];