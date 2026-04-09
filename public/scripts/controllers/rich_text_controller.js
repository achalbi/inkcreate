import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  preventFileAccept(event) {
    event.preventDefault();
  }
}
