module.exports = class ProvedorEstatico {
  id() {
    return "estatico";
  }
  async callApi() {
    return { output: "olá" };
  }
};
