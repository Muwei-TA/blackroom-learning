import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { defaultEndDate, errorText, requestToken } from "../lib/client-rules";

export default class LearningGoalForm extends Component {
  @tracked name = "";
  @tracked commitment = "";
  @tracked startsOn = this.args.today;
  @tracked targetDays = "30";
  @tracked endsOn = defaultEndDate(this.args.today, 30);
  @tracked busy = false;
  @tracked error = "";
  @tracked message = "";
  requestKey = null;
  openedAt = performance.now();
  firstInputAt = null;
  endWasEdited = false;

  @action update(event) {
    const { name, value } = event.target;
    if (!["name", "commitment", "startsOn", "endsOn", "targetDays"].includes(name)) { return; }
    this.firstInputAt ??= performance.now();
    this[name] = value;
    if (name === "endsOn") { this.endWasEdited = true; }
    if (!this.endWasEdited && (name === "startsOn" || name === "targetDays")) {
      this.endsOn = defaultEndDate(this.startsOn, Number(this.targetDays));
    }
  }

  @action async submit(event) {
    event.preventDefault();
    if (this.busy) { return; }
    this.busy = true;
    this.error = "";
    this.message = "";
    try {
      this.requestKey ??= requestToken();
      const result = await ajax("/learning/goals.json", {
        type: "POST",
        data: { name: this.name, commitment: this.commitment, starts_on: this.startsOn,
          ends_on: this.endsOn, target_days: this.targetDays, request_key: this.requestKey,
          typing_duration_msecs: Math.floor(performance.now() - (this.firstInputAt ?? performance.now())),
          composer_open_duration_msecs: Math.floor(performance.now() - this.openedAt) },
      });
      if (this.isDestroying || this.isDestroyed) { return; }
      this.requestKey = null;
      this.message = i18n(result.state === "queued" ? "blackroom_learning.pending_goal" : "blackroom_learning.goal_saved");
      await this.args.onSaved?.(result);
    } catch (error) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = errorText(error, i18n("blackroom_learning.request_failed")); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }

  <template>
    <form class="bl-form" {{on "submit" this.submit}}>
      <p class="bl-hint">{{i18n "blackroom_learning.goal_rules"}}</p>
      <fieldset disabled={{this.busy}}>
        <label><span>{{i18n "blackroom_learning.goal_name"}}</span>
          <input name="name" value={{this.name}} required minlength="2" maxlength="120" {{on "input" this.update}} />
        </label>
        <label><span>{{i18n "blackroom_learning.commitment"}}</span>
          <textarea name="commitment" rows="3" value={{this.commitment}} required minlength="8" maxlength="2000" {{on "input" this.update}}></textarea>
        </label>
        <div class="bl-form-dates">
          <label><span>{{i18n "blackroom_learning.starts_on"}}</span>
            <input name="startsOn" type="date" value={{this.startsOn}} min={{@today}} required {{on "input" this.update}} />
          </label>
          <label><span>{{i18n "blackroom_learning.target_days"}}</span>
            <input name="targetDays" type="number" value={{this.targetDays}} min="1" max="366" step="1" required {{on "input" this.update}} />
          </label>
          <label><span>{{i18n "blackroom_learning.ends_on"}}</span>
            <input name="endsOn" type="date" value={{this.endsOn}} min={{this.startsOn}} required {{on "input" this.update}} />
          </label>
        </div>
        <button class="btn btn-primary" type="submit">{{i18n "blackroom_learning.publish_goal"}}</button>
      </fieldset>
      {{#if this.busy}}<p role="status">{{i18n "blackroom_learning.saving"}}</p>{{/if}}
      {{#if this.error}}<p class="bl-error" role="alert">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p role="status">{{this.message}}</p>{{/if}}
    </form>
  </template>
}
