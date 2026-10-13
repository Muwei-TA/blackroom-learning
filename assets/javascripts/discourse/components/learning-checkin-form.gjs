import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { errorText, requestToken } from "../lib/client-rules";

export default class LearningCheckinForm extends Component {
  @tracked title = `${this.args.goal.name}｜${i18n("blackroom_learning.today_record")}`;
  @tracked raw = "";
  @tracked busy = false;
  @tracked error = "";
  @tracked message = "";
  requestKey = null;
  openedAt = performance.now();
  firstInputAt = null;

  @action update(event) {
    const { name, value } = event.target;
    if (!["title", "raw"].includes(name)) { return; }
    this.firstInputAt ??= performance.now();
    this[name] = value;
  }
  @action async submit(event) {
    event.preventDefault();
    if (this.busy || !this.args.goal.can_checkin) { return; }
    this.busy = true; this.error = ""; this.message = "";
    try {
      this.requestKey ??= requestToken();
      const result = await ajax("/learning/checkins.json", { type: "POST", ignoreUnsent: false, data: {
        goal_id: this.args.goal.id, title: this.title, raw: this.raw, request_key: this.requestKey,
        typing_duration_msecs: Math.floor(performance.now() - (this.firstInputAt ?? performance.now())),
        composer_open_duration_msecs: Math.floor(performance.now() - this.openedAt),
      } });
      if (this.isDestroying || this.isDestroyed) { return; }
      this.requestKey = null;
      this.message = i18n(result.state === "queued" ? "blackroom_learning.pending_checkin" : "blackroom_learning.checkin_saved");
      this.raw = "";
      await this.args.onSaved?.(result);
    } catch (error) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = errorText(error, i18n("blackroom_learning.request_failed")); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  <template>
    <form class="bl-form bl-checkin-form" {{on "submit" this.submit}}>
      <h3>{{i18n "blackroom_learning.checkin_for" name=@goal.name}}</h3>
      <p class="bl-hint">{{i18n "blackroom_learning.checkin_rules"}}</p>
      <fieldset disabled={{this.busy}}>
        <label><span>{{i18n "blackroom_learning.post_title"}}</span>
          <input name="title" value={{this.title}} required maxlength="255" {{on "input" this.update}} />
        </label>
        <label><span>{{i18n "blackroom_learning.post_body"}}</span>
          <textarea name="raw" rows="8" value={{this.raw}} required minlength="8" maxlength="100000" {{on "input" this.update}}></textarea>
        </label>
        <p class="bl-hint">{{i18n "blackroom_learning.markdown_hint"}}</p>
        <button class="btn btn-primary" type="submit">{{i18n "blackroom_learning.publish_checkin"}}</button>
      </fieldset>
      {{#if this.busy}}<p role="status">{{i18n "blackroom_learning.saving"}}</p>{{/if}}
      {{#if this.error}}<p class="bl-error" role="alert">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p role="status">{{this.message}}</p>{{/if}}
    </form>
  </template>
}
